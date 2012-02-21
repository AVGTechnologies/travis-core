require 'ostruct'
require 'active_support/core_ext/string/inflections'
require 'core_ext/ostruct/hash_access'
require 'active_support/json'

# Github::Api wraps some parts of the Github API for
#
#  * easier access (e.g.  Github::Commit#branch parses the `ref` value
#    contained in the Github payload and returns just the branch name) as
#    well as
#
#  * adding some Travis CI specific logic (e.g. Github::Repository#owner_email
#    either returns the given value from the Github payload OR fetches the
#    owner OR fetches all owners of an organization and returns the respective
#    emails).
#
# TODO: either port this to Octokit or use Hashr instead of OpenStruct

module Github
  module Api
    class << self
      def included(base)
        base.extend(ClassMethods)
      end
    end

    module ClassMethods
      def fetch(data)
        new(data).fetch
      end
    end

    def fetch
      uri = URI.parse("http://github.com/api/v2/json/#{path}")
      response = Net::HTTP.get_response(uri)
      data = ActiveSupport::JSON.decode(response.body)
      key  = self.class.name.demodulize.underscore
      data.replace(data[key]) if data.key?(key)
      self.class.new(data)
    end
  end

  module ServiceHook
    class Payload < OpenStruct
      attr_reader :payload

      def initialize(payload)
        @payload = payload
        payload = ActiveSupport::JSON.decode(payload) if payload.is_a?(String)
        super(payload)
      end

      def repository
        @repository ||= Repository.new(super)
      end

      def last_commit
        commits.last
      end

      def commits
        @commits ||= Array(self['commits']).map do |commit|
          Commit.new(commit.merge('ref' => ref, 'compare_url' => compare_url), repository)
        end
      end

      def compare_url
        self['compare']
      end
    end
  end

  class Repository < OpenStruct
    include Api

    ATTR_NAMES = [:name, :description, :url, :owner_name, :owner_email]

    def to_hash
      ATTR_NAMES.inject({}) { |result, name| result.merge(name => self.send(name)) }
    end

    def owner_name
      owner.is_a?(Hash) ? owner['name'] : owner
    end

    def owner_email
      if owner.is_a?(Hash) && email = owner['email']
        return email if email
      end

      if organization
        Organization.fetch(:name => organization).member_emails
      else
        User.fetch(:name => owner_name).email
      end
    end

    def path
      "repos/show/#{owner_name}/#{name}"
    end

    def private?
      self['private']
    end
  end

  class Commit < OpenStruct
    ATTR_NAMES = [:commit, :message, :branch, :committed_at, :committer_name, :committer_email, :author_name, :author_email, :compare_url]

    def initialize(data, repository)
      data['author'] ||= {}
      data['repository']  = repository
      super(data)
    end

    def to_hash
      ATTR_NAMES.inject({}) { |result, name| result.merge(name => self.send(name)) }
    end

    def commit
      self['id']
    end

    def branch
      (self['ref'] || '').gsub(/^refs\/heads\//, '')
    end

    def committed_at
      self['timestamp']
    end

    def committer
      self['committer'] || {}
    end

    def committer_name
      committer['name']
    end

    def committer_email
      committer['email']
    end

    def author
      self['author'] || {}
    end

    def author_name
      author['name']
    end

    def author_email
      author['email']
    end

    def compare_url
      self['compare_url']
    end
  end

  class Organization < OpenStruct
    include Api

    def member_emails
      users.map { |user| user['email'] }.select(&:present?).join(',')
    end

    def path
      "organizations/#{name}/public_members"
    end
  end

  class User < OpenStruct
    include Api

    def path
      "user/show/#{name}"
    end
  end
end


