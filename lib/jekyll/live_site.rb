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
        page.render(self.layouts, payload)
      end

      if page.write(self.dest)
        yield page.destination(self.dest)
      end
    end
  end

  def resolve_file filename
    path = File.expand_path filename, self.source
    dir, name = File.split path
    entries = Dir.chdir(dir) { filter_entries([name]) }
    return if entries.empty?

    if path.include? '/_posts/'
      if page = self.posts.find { |p| p.filename == path }
        yield page
      end
    elsif path.include? '/_layouts/'
      if pair = self.layouts.find { |_, p| p.filename == path }
        layout_name = pair[0]
        [self.posts, self.pages].each do |group|
          group.each { |p| yield p if using_layout?(layout_name, p) }
        end
      end
    else
      [self.pages, self.static_files].each do |group|
        if page = group.find { |p| p.filename == path }
          yield page
        end
      end
    end
  end

  def using_layout? name, page, seen = nil
    if using = page.data['layout'] and (seen.nil? or !seen.include?(using))
      using == name or using_layout?(name, self.layouts[using], (seen || []) << using)
    end
  end
end

end
