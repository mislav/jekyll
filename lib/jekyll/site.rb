module Jekyll

  class Site
    attr_accessor :config, :layouts, :posts, :categories, :exclude,
                  :source, :dest, :lsi, :pygments, :permalink_style, :tags

    # Initialize the site
    #   +config+ is a Hash containing site configurations details
    #
    # Returns <Site>
    def initialize(config)
      self.config          = config.clone

      self.source          = config['source']
      self.dest            = config['destination']
      self.lsi             = config['lsi']
      self.pygments        = config['pygments']
      self.permalink_style = config['permalink'].to_sym
      self.exclude         = config['exclude'] || []

      self.reset
      self.setup
    end

    def reset
      self.layouts         = {}
      self.posts           = []
      self.categories      = Hash.new { |hash, key| hash[key] = [] }
      self.tags            = Hash.new { |hash, key| hash[key] = [] }
    end

    def setup
      # Check to see if LSI is enabled.
      require 'classifier' if self.lsi

      # Set the Markdown interpreter (and Maruku self.config, if necessary)
      case self.config['markdown']
        when 'rdiscount'
          begin
            require 'rdiscount'

            def markdown(content)
              RDiscount.new(content).to_html
            end

          rescue LoadError
            puts 'You must have the rdiscount gem installed first'
          end
        when 'maruku'
          begin
            require 'maruku'

            def markdown(content)
              Maruku.new(content).to_html
            end

            if self.config['maruku']['use_divs']
              require 'maruku/ext/div'
              puts 'Maruku: Using extended syntax for div elements.'
            end

            if self.config['maruku']['use_tex']
              require 'maruku/ext/math'
              puts "Maruku: Using LaTeX extension. Images in `#{self.config['maruku']['png_dir']}`."

              # Switch off MathML output
              MaRuKu::Globals[:html_math_output_mathml] = false
              MaRuKu::Globals[:html_math_engine] = 'none'

              # Turn on math to PNG support with blahtex
              # Resulting PNGs stored in `images/latex`
              MaRuKu::Globals[:html_math_output_png] = true
              MaRuKu::Globals[:html_png_engine] =  self.config['maruku']['png_engine']
              MaRuKu::Globals[:html_png_dir] = self.config['maruku']['png_dir']
              MaRuKu::Globals[:html_png_url] = self.config['maruku']['png_url']
            end
          rescue LoadError
            puts "The maruku gem is required for markdown support!"
          end
        else
          raise "Invalid Markdown processor: '#{self.config['markdown']}' -- did you mean 'maruku' or 'rdiscount'?"
      end
    end

    def textile(content)
      RedCloth.new(content).to_html
    end

    # Do the actual work of processing the site and generating the
    # real deal.
    #
    # Returns nothing
    def process
      self.reset
      self.read_layouts
      self.find_posts
      self.transform_pages
      self.write_posts
    end

    # Read all the files in <source>/_layouts into memory for later use.
    #
    # Returns nothing
    def read_layouts
      base = File.join(self.source, "_layouts")
      entries = []
      Dir.chdir(base) { entries = filter_entries(Dir['*.*']) }

      entries.each do |f|
        name = f.split(".")[0..-2].join(".")
        self.layouts[name] = Layout.new(self, base, f)
      end
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end
    
    # Find all the nested "_posts" directories in <source>
    def find_posts
      directories = Dir.chdir(self.source) do
        Dir['**/_posts'].select { |dir| File.directory?(dir) }
      end
      directories.each { |dir| read_posts(dir) }
    end

    # Read all the files in <dir> and create a new Post object with each one.
    #
    # Returns nothing
    def read_posts(dir)
      entries = Dir.chdir(File.join(self.source, dir)) { filter_entries(Dir['**/*']) }
      # get the parent directory above "_posts"
      base = File.dirname(dir)
      base = '' if '.' == base

      # first pass processes, but does not yet render post content
      entries.each do |f|
        if Post.valid?(f)
          post = Post.new(self, self.source, base, f)

          if post.published
            self.posts << post
            post.categories.each { |c| self.categories[c] << post }
            post.tags.each { |c| self.tags[c] << post }
          end
        end
      end

      self.posts.sort!

      # second pass renders each post now that full site payload is available
      self.posts.each do |post|
        post.render(self.layouts, site_payload)
      end

      self.categories.values.map { |ps| ps.sort! { |a, b| b <=> a} }
      self.tags.values.map { |ps| ps.sort! { |a, b| b <=> a} }
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end

    # Write each post to <dest>/<year>/<month>/<day>/<slug>
    #
    # Returns nothing
    def write_posts
      self.posts.each do |post|
        post.write(self.dest)
      end
    end

    # Copy all regular files from <source> to <dest>/ ignoring
    # any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~") or contain site content (start with "_")
    # unless they are "_posts" directories or web server files such as
    # '.htaccess'
    #   The +dir+ String is a relative path used to call this method
    #            recursively as it descends through directories
    #
    # Returns nothing
    def transform_pages(dir = '')
      base = File.join(self.source, dir)
      entries = filter_entries(Dir.entries(base))
      directories, files = entries.partition { |e| File.directory?(File.join(base, e)) }

      [directories, files].each do |entries|
        entries.each do |f|
          if File.directory?(File.join(base, f))
            next if self.dest.sub(/\/$/, '') == File.join(base, f)
            transform_pages(File.join(dir, f))
          elsif Pager.pagination_enabled?(self.config, f)
            paginate_posts(f, dir)
          else
            first3 = File.open(File.join(self.source, dir, f)) { |fd| fd.read(3) }

            if first3 == "---"
              # file appears to have a YAML header so process it as a page
              page = Page.new(self, self.source, dir, f)
              page.render(self.layouts, site_payload)
              page.write(self.dest)
            else
              # otherwise copy the file without transforming it
              FileUtils.mkdir_p(File.join(self.dest, dir))
              FileUtils.cp(File.join(self.source, dir, f), File.join(self.dest, dir, f))
            end
          end
        end
      end
    end

    # Constructs a hash map of Posts indexed by the specified Post attribute
    #
    # Returns {post_attr => [<Post>]}
    def post_attr_hash(post_attr)
      # Build a hash map based on the specified post attribute ( post attr => array of posts )
      # then sort each array in reverse order
      hash = Hash.new { |hash, key| hash[key] = Array.new }
      self.posts.each { |p| p.send(post_attr.to_sym).each { |t| hash[t] << p } }
      hash.values.map { |sortme| sortme.sort! { |a, b| b <=> a} }
      return hash
    end

    # The Hash payload containing site-wide data
    #
    # Returns {"site" => {"time" => <Time>,
    #                     "posts" => [<Post>],
    #                     "categories" => [<Post>]}
    def site_payload
      {"site" => self.config.merge({
          "time"       => Time.now,
          "posts"      => self.posts.sort { |a,b| b <=> a },
          "categories" => post_attr_hash('categories'),
          "tags"       => post_attr_hash('tags')})}
    end

    # Filter out any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~") or contain site content (start with "_")
    # unless they are '.htaccess'
    def filter_entries(entries)
      entries = entries.reject do |e|
        unless '.htaccess' == e
          ['.', '_', '#'].include?(e[0..0]) || e[-1..-1] == '~' || self.exclude.include?(e)
        end
      end
    end

    # Paginates the blog's posts. Renders the index.html file into paginated directories, ie: page2, page3...
    # and adds more site-wide data
    #
    # {"paginator" => { "page" => <Number>,
    #                   "per_page" => <Number>,
    #                   "posts" => [<Post>],
    #                   "total_posts" => <Number>,
    #                   "total_pages" => <Number>,
    #                   "previous_page" => <Number>,
    #                   "next_page" => <Number> }}
    def paginate_posts(file, dir)
      all_posts = self.posts.sort { |a,b| b <=> a }
      pages = Pager.calculate_pages(all_posts, self.config['paginate'].to_i)
      pages += 1
      (1..pages).each do |num_page|
        pager = Pager.new(self.config, num_page, all_posts, pages)
        page = Page.new(self, self.source, dir, file)
        page.render(self.layouts, site_payload.merge({'paginator' => pager.to_hash}))
        suffix = "page#{num_page}" if num_page > 1
        page.write(self.dest, suffix)
      end
    end
  end
end
