require 'spec_helper'

describe Travis::Github::Services::FindOrCreateOrg do
  include Support::ActiveRecord
  include Travis::Testing::Stubs


  let(:service) { described_class.new(nil, params) }

  attr_reader :params

  before :each do
  end

  it 'finds an existing organization' do
    organization = Factory(:org, login: 'foobar', github_id: 999)
    @params = { github_id: organization.github_id, login: 'foobar' }
    expect(service.run).to eq(organization)
  end

  it 'gets login from data if login is not available in find' do
    organization = Factory(:org, login: 'foobar', github_id: 999)
    @params = { github_id: 999 }
    service.expects(:data).at_least_once.returns({ 'login' => 'foobarbaz' })

    expect(service.run).to eq(organization)

    expect(organization.reload.login).to eq('foobarbaz')
  end

  it 'updates repositories owner_name and nullifies other users or orgs\' login if login is changed' do
    organization = Factory(:org, login: 'foobar', github_id: 999)
    organization.repositories << Factory(:repository, owner_name: 'foobar', name: 'foo', owner: organization)
    organization.repositories << Factory(:repository, owner_name: 'foobar', name: 'bar', owner: organization)

    # repository with the same owner_id, but which is of user type
    user = Factory(:user, id: organization.id)
    ActiveRecord::Base.connection.execute("SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));")
    user_repository = Factory(:repository, owner_name: 'dont_change_me', owner: user)
    user.repositories << user_repository

    same_login_user = Factory(:user, login: 'foobarbaz', github_id: 998)
    same_login_org  = Factory(:org, login: 'foobarbaz', github_id: 997)
    @params = { github_id: organization.github_id, login: 'foobarbaz' }
    expect(service.run).to eq(organization)

    expect(organization.reload.repositories.map(&:owner_name).uniq).to eq(['foobarbaz'])
    expect(same_login_user.reload.login).to be_nil
    expect(same_login_org.reload.login).to be_nil
    expect(user_repository.reload.owner_name).to eq('dont_change_me')
  end

  it 'creates an organization from github' do
    @params = { github_id: 999 }
    service.stubs(:data).returns({'name' => 'Foo Bar', 'login' => 'foobar', 'id' => 999})
    expect {
      service.run
    }.to change { Organization.count }.by(1)

    organization = Organization.first
    expect(organization.name).to eq('Foo Bar')
    expect(organization.login).to eq('foobar')
    expect(organization.github_id).to eq(999)
  end

  it 'creates a organization from github and nullifies login if other organization has the same login' do
    @params = { github_id: 999 }
    service.stubs(:data).returns({'name' => 'Foo Bar', 'login' => 'foobar', 'id' => 999})

    old_user = Factory(:user, github_id: 998, login: 'foobar')
    old_org  = Factory(:org, github_id: 1000, login: 'foobar')

    new_org = nil
    expect {
      new_org = service.run
    }.to change { Organization.count }.by(1)

    expect(old_user.reload.login).to be_nil
    expect(old_org.reload.login).to be_nil
    expect(new_org.login).to eq('foobar')
  end

  xit 'raises a GithubApi error if the organization could not be retrieved' do
  end
end
