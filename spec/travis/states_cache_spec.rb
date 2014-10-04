require 'spec_helper'

module Travis
  describe StatesCache do
    include ::Support::ActiveRecord

    let(:adapter) { StatesCache::TestAdapter.new }
    subject { StatesCache.new(adapter: adapter) }

    it 'allows to fetch state' do
      adapter.expects(:fetch).with(1, 'master').returns({'state' => 'passed'})
      expect(subject.fetch_state(1, 'master')).to eq(:passed)
    end

    it 'gets data from build if it\'s given instead of raw data' do
      build = Factory(:build, finished_at: Time.new(2013, 1, 1, 10, 0, 0), state: :passed)
      data = { finished_at: '2013-01-01T10:00:00Z', state: 'passed' }.stringify_keys

      adapter.expects(:write).with(1, 'master', data)
      subject.write(1, 'master', build)
    end

    it 'delegates #write to adapter' do
      data = { finished_at: '2013-04-22T22:10:00', state: 'passed' }.stringify_keys
      adapter.expects(:write).with(1, 'master', data)
      subject.write(1, 'master', data)
    end

    it 'delegates #fetch to adapter' do
      adapter.expects(:fetch).with(1, 'master').returns({ foo: 'bar' })
      expect(subject.fetch(1, 'master')).to eq({ foo: 'bar' })
    end

    describe 'integration' do
      let(:client) { Dalli::Client.new('localhost:11211') }
      let(:adapter) { StatesCache::MemcachedAdapter.new(client: client) }

      before do
        begin
          client.flush
        rescue Dalli::DalliError => e
          skip "Dalli can't run properly, skipping. Cause: #{e.message}"
        end
      end

      it 'saves the state for given branch and globally' do
        data = { finished_at: '2013-04-22T22:10:00', state: 'passed' }.stringify_keys
        subject.write(1, 'master', data)
        expect(subject.fetch(1)['state']).to eq('passed')
        expect(subject.fetch(1, 'master')['state']).to eq('passed')

        expect(subject.fetch(2)).to be_nil
        expect(subject.fetch(2, 'master')).to be_nil
      end

      it 'updates the state only if the info is newer' do
        data = { finished_at: '2013-01-01T12:00:00', state: 'passed' }.stringify_keys
        subject.write(1, 'master', data)

        expect(subject.fetch(1, 'master')['state']).to eq('passed')

        data = { finished_at: '2013-02-01T12:00:00', state: 'failed' }.stringify_keys
        subject.write(1, 'development', data)

        expect(subject.fetch(1, 'master')['state']).to eq('passed')
        expect(subject.fetch(1, 'development')['state']).to eq('failed')
        expect(subject.fetch(1)['state']).to eq('failed')

        data = { finished_at: '2013-01-15T12:00:00', state: 'errored' }.stringify_keys
        subject.write(1, 'master', data)

        expect(subject.fetch(1, 'master')['state']).to eq('errored')
        expect(subject.fetch(1, 'development')['state']).to eq('failed')
        expect(subject.fetch(1)['state']).to eq('failed')
      end

      it 'handles connection errors gracefully' do
        data = { finished_at: '2013-04-22T22:10:00', state: 'passed' }.stringify_keys
        client = Dalli::Client.new('illegalserver:11211')
        adapter = StatesCache::MemcachedAdapter.new(client: client)
        adapter.jitter = 0.005
        subject = StatesCache.new(adapter: adapter)
        expect {
          subject.write(1, 'master', data)
        }.to raise_error(Travis::StatesCache::CacheError)

        expect {
          subject.fetch(1)
        }.to raise_error(Travis::StatesCache::CacheError)
      end
    end

    describe StatesCache::MemcachedAdapter do
      let(:client) { stub('client') }
      subject { StatesCache::MemcachedAdapter.new(client: client) }

      it 'fetches the data for given id as JSON' do
        json = '{ "state": "passed", "finished_at": "2013-04-22T22:10" }'
        client.expects(:get).with('state:1').returns(json)

        expect(subject.fetch(1)).to eq({ 'state' => 'passed', 'finished_at' => '2013-04-22T22:10' })
      end

      it 'writes for both a branch and default state' do
        time = '2013-04-22T22:10'
        data = { 'finished_at' => time }

        subject.expects(:update?).with(1, nil, time).returns(true)
        subject.expects(:update?).with(1, 'master', time).returns(true)

        client.expects(:set).with('state:1', data.to_json)
        client.expects(:set).with('state:1-master', data.to_json)

        subject.write(1, 'master', data)
      end

      context '#update?' do
        it 'returns true if persisted data is older than data passed as an argument' do
          subject.expects(:fetch).with(1, nil).returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, nil, '2013-04-22T22:14')).to be_truthy

          subject.expects(:fetch).with(1, 'master').returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, 'master', '2013-04-22T22:14')).to be_truthy
        end

        it 'returns false if persisted data is younger than data passed as an argument' do
          subject.expects(:fetch).with(1, nil).returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, nil, '2013-04-22T22:10')).to be_falsey

          subject.expects(:fetch).with(1, 'master').returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, 'master', '2013-04-22T22:10')).to be_falsey
        end

        it 'returns true if persisted data is the same age' do
          subject.expects(:fetch).with(1, nil).returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, nil, '2013-04-22T22:12')).to be_falsey

          subject.expects(:fetch).with(1, 'master').returns({ 'finished_at' => '2013-04-22T22:12' })
          expect(subject.update?(1, 'master', '2013-04-22T22:12')).to be_falsey
        end
      end
    end
  end
end
