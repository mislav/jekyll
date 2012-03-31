require 'guard/guard'
require 'jekyll/live_site'

class Guard::Jekyll < Guard::Guard
  attr_reader :workdir

  def initialize(watchers = [], options = {})
    super
    @site = nil
    @workdir = Dir.pwd
  end

  def init_site
    jekyll_options = ::Jekyll::configuration(@options)
    @site = ::Jekyll::LiveSite.new(jekyll_options)
    @destination = File.join(File.expand_path(jekyll_options['destination'], @workdir), '')
    print "Rebuilding Jekyll site... "
    @site.process
    puts "done."
  end
  alias_method :start, :init_site
  alias_method :reload, :init_site
  alias_method :run_all, :init_site

  def run_on_change paths
    init_site if paths.include? '_config.yml'
    return if @site.nil?
    render_files paths
  end

  def filter_files paths
    paths.reject { |path| in_destination? path }
  end

  def in_destination? path
    File.expand_path(path, workdir).index(@destination) == 0
  end

  def render_files paths
    changed = []
    @site.process_files filter_files(paths) do |processed|
      relative = processed.sub("#{workdir}/", '')
      puts "Jekyll: #{relative}"
      changed << relative
    end

    notify changed if changed.any?
  end

  def notify changed_files
    ::Guard.guards.each do |guard|
      next if self.class === guard
      paths = ::Guard::Watcher.match_files(guard, changed_files)
      guard.run_on_change(paths) unless paths.empty?
    end
  end
end
