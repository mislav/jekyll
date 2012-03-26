module Jekyll

  # Highlights code using Pygments.rb
  #
  # The syntax for the tag is "highlight <lang> [<opt>[=<value>], ...]".
  #
  # See `pygmentize -L lexers` for the list of available languages.
  #
  # Options:
  #
  # cssclass      - CSS class for the wrapping DIV tag (default: 'highlight')
  # classprefix   - string to prepend to all generated CSS class names
  #                 (default: '')
  # hl_lines      - list of lines to be highlighted (default: none)
  # linenos       - show line numbers in "inline" style; when set to "table"
  #                 render line numbers in a separate table column
  #                 (default: false)
  # linenostart   - initial line number (default: 1)
  # lineanchors   - a string prefix that triggers wrapping each output line
  #                 in an anchor tag with name in "<prefix>-<line>" format
  #                 (default: none)
  # anchorlinenos - in combination with `linenos=table` and `lineanchors`, turn
  #                 line numbers into links to individual lines (default: false)
  #
  # Examples
  #
  #   {% highlight ruby %}
  #   ... ruby code ...
  #   {% endhighlight %}
  #
  #   # Show line numbers:
  #   {% highlight js linenos linenostart=5 %}
  #
  #   # Highlight lines 1,3,5:
  #   {% highlight css hl_lines=1_3_5 %}
  #
  class HighlightBlock < Liquid::Block
    include Liquid::StandardFilters

    # The regular expression syntax checker. Start with the language specifier.
    # Follow that by zero or more space separated options that take one of two
    # forms:
    #
    # 1. name
    # 2. name=value
    SYNTAX = /^([a-zA-Z0-9.+#-]+)((\s+\w+(=[\w-]+)?)*)$/

    def initialize(tag_name, markup, tokens)
      super
      @options = { :encoding => 'utf-8' }
      if markup.strip =~ SYNTAX
        @lang = $1
        $2.to_s.split.inject(@options) do |opts, opt|
          process_option(*opt.split('=', 2)) do |key, value|
            opts[key] = value
          end
          opts
        end
      else
        raise SyntaxError.new("Syntax Error in 'highlight' - Valid syntax: highlight <lang> [linenos]")
      end
    end

    # Validates option for Pygments.
    #
    # Yields key, value if the option has value.
    #
    # Raises ArgumentError for unsupported options.
    def process_option(key, value = nil)
      case key
      when 'linenos'       then value ||= 'inline'
      when 'hl_lines'      then value = value.to_s.split(/\D/)
      when 'anchorlinenos' then value ||= true
      when 'lineanchors', 'linenostart', 'cssclass', 'classprefix'
        # these have a string value
      else
        raise ArgumentError, "unsupported Pygments option: #{key}"
      end

      yield key, value unless value.nil?
    end

    def render(context)
      if context.registers[:site].pygments
        render_pygments(context, super)
      else
        render_codehighlighter(context, super)
      end
    end

    def render_pygments(context, code)
      pretty = Pygments.highlight code, :lexer => @lang, :options => @options
      output = add_code_tags(pretty, @lang)
      output = context["pygments_prefix"] + output if context["pygments_prefix"]
      output = output + context["pygments_suffix"] if context["pygments_suffix"]
      output
    end

    def render_codehighlighter(context, code)
      #The div is required because RDiscount blows ass
      <<-HTML
<div>
  <pre><code class='#{@lang}'>#{h(code).strip}</code></pre>
</div>
      HTML
    end

    def add_code_tags(code, lang)
      # Add nested <code> tags to code blocks
      code = code.sub(/<pre>/,'<pre><code class="' + lang + '">')
      code = code.sub(/<\/pre>/,"</code></pre>")
    end

  end

end

Liquid::Template.register_tag('highlight', Jekyll::HighlightBlock)
