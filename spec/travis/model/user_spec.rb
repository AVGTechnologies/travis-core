require 'spec_helper'
require 'support/active_record'

describe User do
  include Support::ActiveRecord

  let (:user)    { FactoryGirl.build(:user) }
  let (:payload) { GITHUB_PAYLOADS[:oauth] }

  describe 'find_or_create_for_oauth' do
    def user(payload)
      User.find_or_create_for_oauth(payload)
    end

    it 'marks new users as such' do
      user(payload).should be_recently_signed_up
      user(payload).should_not be_recently_signed_up
    end

    it 'updates changed attributes' do
      user(payload).login.should == 'john'
    end
  end

  describe 'user_data_from_oauth' do
    it 'returns required data' do
      User.user_data_from_oauth(payload).should == {
        "name"                => "John",
        "email"               => "john@email.com",
        "login"               => "john",
        "github_id"           => "234423",
        "github_oauth_token"  => "1234567890abcdefg"
      }
    end
  end

  describe 'profile_image_hash' do
    it 'returns a MD5 hash of the email if an email is set' do
      user.profile_image_hash.should == Digest::MD5.hexdigest(user.email)
    end

    it 'returns 32 zeros if no email is set' do
      user.email = nil
      user.profile_image_hash.should == '0' * 32
    end
  end

  xit 'github_repositories should be specified'

  describe 'active_by_name' do
    xit 'returns a hash of active by name attributes (can be scoped)' do
      Factory(:repository, :active => true, :owner_name => 'svenfuchs', :name => 'minimal')
      Factory(:repository, :active => false, :owner_name => 'svenfuchs', :name => 'gem-release')
      Factory(:repository, :active => true, :owner_name => 'josevalim', :name => 'enginex')

      result = Repository.where(:owner_name => 'svenfuchs').active_by_name
      result.should == { 'minimal' => true, 'gem-release' => false }
    end
  end
end
