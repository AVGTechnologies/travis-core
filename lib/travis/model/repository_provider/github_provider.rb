class GithubProvider < RepositoryProvider
    attr_reader :repository

  def initiaize(repository)
    @repository = repository
  end

  def source_url
    (repository.private? || private_mode?) ? "git@#{source_host}:#{repository.slug}.git": "git://#{source_host}/#{repository.slug}.git"
  end

  def content_url(options)
    GH.full_url("repos/#{repository.slug}/contents/#{options[:path]}?ref=#{options[:ref]}").to_s
  end

  def fetch_content(config_url)
    content = GH[config_url]['content']
    Travis.logger.warn("[request:fetch_config] Empty content for #{config_url}") if content.nil?
    content = content.to_s.unpack('m').first
    Travis.logger.warn("[request:fetch_config] Empty unpacked content for #{config_url}, content was #{content.inspect}") if content.nil?
    nbsp = "\xC2\xA0".force_encoding("binary")
    content = content.gsub(/^(#{nbsp})+/) { |match| match.gsub(nbsp, " ") }

    content
  end

  def source_host
    Travis.config.github.source_host || 'github.com'
  end

  private

  def private_mode?
    source_host != 'github.com'
  end
end


