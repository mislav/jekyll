require 'jekyll'
require 'jekyll/site'

module Jekyll

class LiveSite < Site
  def process_files files
    pages = []
    Array(files).each do |filename|
      resolve_file(filename) { |page| pages << page }
    end

    return false if pages.empty?

    payload = nil

    for page in pages
      if page.respond_to? :render
        payload ||= self.site_payload
        page.read_yaml('', page.filename)
        # TODO: remove post if stopped being published?
        page.render(self.layouts, payload)
      end

      if page.write(self.dest)
        yield page.destination(self.dest)
      end
    end
  end

  def resolve_file filename
    path = File.expand_path filename, self.source
    file = ContentFile.new path, self.source, self.dest, self.method(:allow_file?)
    unless file.valid?
      warn "invalid file: #{file.path}"
      return
    end

    case file.type
    when :post
      page = self.posts.find { |p| p.filename == file.path }
      page ||= create_post(file.relative_dir, file.name)
      yield page
    when :layout
      if pair = self.layouts.find { |_, p| p.filename == file.path }
        layout_name = pair[0]
      else
        layout_name = file.name.sub(/\.[^.]+$/, '')
        self.layouts[layout_name] = Layout.new(self, file.dir, file.name)
      end
      [self.posts, self.pages].each do |group|
        group.each { |p| yield p if using_layout?(layout_name, p) }
      end
    when :file
      page = nil
      [self.pages, self.static_files].each do |group|
        if page = group.find { |p| p.filename == file.path }
          break
        end
      end

      page ||= if has_yaml_header? file.path
                 new_page = Page.new(self, self.source, file.dir, file.name)
                 self.pages << new_page
                 new_page
               else
                 new_file = StaticFile.new(self, self.source, file.dir, file.name)
                 self.static_files << new_file
                 new_file
               end

      yield page
    else
      raise "unknown file type: #{file.type}"
    end
  rescue InvalidPost => e
    warn e.message
  end

  class ContentFile
    attr_reader :path, :dir, :name
    alias to_s path

    TYPE_MAPPING = {
      '_layouts'  => :layout,
      '_includes' => :include,
      '_posts'    => :post
    }

    def initialize path, source, dest, allowed_checker = nil
      @path = path
      @source = source
      @destination = dest
      @allowed_checker = allowed_checker || lambda {|f| true }
      @dir, @name = File.split @path
      @type = :file
      @valid_dir = nil
    end

    def type
      deep_check
      @type
    end

    def relative_dir
      @relative_dir ||= self.dir.sub(File.join(@source, ''), '')
    end

    def valid?
      !File.symlink? path and
        @allowed_checker.call(name) and
          deep_check
    end

    def deep_check
      return @valid_dir unless @valid_dir.nil?
      @valid_dir = valid_dir? self.dir
    end

    def valid_dir? path
      if path == '/'
        false
      elsif path == @destination
        false
      elsif path == @source
        true
      elsif File.symlink? path
        false
      else
        dir, name = File.split path
        if type = TYPE_MAPPING[name]
          @type = type
        elsif !@allowed_checker.call(name)
          return false
        end
        valid_dir? dir
      end
    end
  end

  class InvalidPost < StandardError; end

  def create_post dir, name
    path = File.join dir, name
    # TODO: hack
    dir, name = path.split('/_posts/', 2)

    if Post.valid? name
      post = Post.new(self, self.source, dir, name)

      if publish_post? post
        self.posts << post
        post.categories.each { |c| self.categories[c] << post }
        post.tags.each { |c| self.tags[c] << post }
        post
      else
        raise InvalidPost, "post not publishable: #{post.inspect}"
      end
    else
      raise InvalidPost, "not a valid post: #{name.inspect}"
    end
  end

  def publish_post? post
    post.published && (self.future || post.date <= self.time)
  end

  def using_layout? name, page, seen = nil
    if using = page.data['layout'] and (seen.nil? or !seen.include?(using))
      using == name or using_layout?(name, self.layouts[using], (seen || []) << using)
    end
  end

  def has_yaml_header? file
    '---' == File.open(file) { |fd| fd.read(3) }
  end

  FILTER_PREFIXES = %w[ . _ # ]
  FILTER_SUFFIXES = %w[ ~ ]

  # Filter out any files/directories that are hidden or backup files (start
  # with ".", "_", or "#", or end with "~"), or are excluded by the site
  # configuration, unless they are whitelisted by the site configuration.
  #
  # To be able to check symlinks, this method expects to be run from the
  # directory where entries originate.
  #
  # entries - The Array of file/directory entries to filter.
  #
  # Returns the Array of filtered entries.
  def filter_entries(entries)
    entries.select { |entry|
      allow_file? entry and !File.symlink? entry
    }
  end

  def allow_file? entry
    whitelisted_file? entry or
      (allow_file_name? entry and !blacklisted_file? entry)
  end

  def allow_file_name? entry
    !(FILTER_PREFIXES.include? entry[0,1] or
      FILTER_SUFFIXES.include? entry[-1,1])
  end

  def whitelisted_file? entry
    self.include.include? entry
  end

  def blacklisted_file? entry
    self.exclude.include? entry
  end
end

end
