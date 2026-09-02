# frozen_string_literal: true

require 'loofah'

# Removes unsafe feed markup with Loofah's maintained HTML safelist.
module FeedHtmlSanitizer
  module_function

  def sanitize(html)
    Loofah.html5_fragment(html.to_s).scrub!(:prune).to_html
  end
end
