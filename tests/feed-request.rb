require 'optparse'
require 'inifile'
require 'uri'

def validate_url(url)
  uri = URI.parse(url)
  raise OptionParser::InvalidOption.new("invalid url: #{url}") unless %w( http https ).include?(uri.scheme) && uri.host.include?('.')
end

def validate_language_code(code)
  /\A[A-Za-z]{2}\z/i === code ? code.downcase : (raise OptionParser::InvalidOption.new("invalid location: #{code}"))
end

def get_content(title, feed, link, avatar, location=nil)
  {
    'title' => title,
    'feed' => feed,
    'link' => link,
    'location' => location,
    'avatar' => avatar
  }.compact
end

def initialize_section
  IniFile.load('planet.ini')
end

def write_ini(ini)
  sorted_ini = IniFile.new(encoding: 'UTF-8')
  ini.each_section do |section|
    next if section == 'global'
    sorted_ini[section] = ini[section]
  end
  sorted_ini.write(filename: 'planet.ini')
end

def parse_options
  options = {}
  OptionParser.new do |op|
    op.banner = "Usage: feed-request.rb [options]"
    op.on("-t", "--title TITLE", "Blog title") {|v| options[:title] = v }
    op.on("-f", "--feed FEED", "Feed URL")   {|v| validate_url(v); options[:feed] = v }
    op.on("-l", "--link LINK", "Link URL")   {|v| validate_url(v); options[:link] = v }
    op.on("-a", "--avatar AVATAR", "Avatar image link")  {|v| validate_url(v); options[:avatar] = v }
    op.on("-c", "--location LOCATION", "Location") {|v| options[:location] = validate_language_code(v) }
  end.parse!
  options.compact!
  raise OptionParser::MissingArgument if %i[title feed link avatar].any? { |k| options[k].nil? }
  options
end

def main
  options = parse_options
  section_name = options[:title].downcase.tr(' ', '_')
  ini = initialize_section
  ini[section_name] = get_content(options[:title], options[:feed], options[:link], options[:avatar], options[:location])
  write_ini(ini)
end

main