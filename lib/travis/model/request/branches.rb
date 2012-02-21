class Request

  # Logic that figures out whether a branch is in- or excluded (white- or
  # blacklisted) by the configuration (`.travis.yml`)
  #
  # TODO somehow feels wrong. maybe this should rather be on a Request::Approval
  # or Request::Vetting as we might vet based on other things than just the
  # branch?
  module Branches
    def branch_included?(branch)
      !included_branches || included_branches.include?(branch)
    end

    def branch_excluded?(branch)
      excluded_branches && excluded_branches.include?(branch)
    end

    def included_branches
      branches_config[:only]
    end

    def excluded_branches
      branches_config[:except]
    end

    def branches_config
      case config.try(:[], :branches)
      when String
        { :only => config[:branches].split(',').map(&:strip) }
      when Array
        { :only => config[:branches] }
      when Hash
        config[:branches] # TODO should split :only and :except values if these are strings. maybe use a specialized Hashr class.
      else
        {}
      end
    end
  end
end
