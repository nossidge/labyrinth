require 'fileutils'

# Configuration
SOURCE_DIR = 'private'
TARGET_DIR = 'public'
WIP_DIR = 'wip'

def get_formatted_title(dir_path)
  File.basename(dir_path).split('-').map(&:capitalize).join(' ')
end

def generate_dir_files(dir_path)
  all_corridor_dirs = Dir.glob(File.join(dir_path, 'corridors', '*/')).sort
  corridor_dirs = all_corridor_dirs.reject do |d|
    File.exist?(File.join(d, '.wip'))
  end

  all_room_dirs = Dir.glob(File.join(dir_path, 'rooms', '*/')).sort
  room_dirs = all_room_dirs.reject do |d|
    File.exist?(File.join(d, '.wip'))
  end

  # Corridors for JS (relative to common/labyrinthPages.js, i.e., ../../corridors/...)
  corridors_for_js = corridor_dirs.map { |d| d.sub("#{dir_path}/", '') + "index.html" }

  # 1. Generate common/labyrinthPages.js
  js_path = File.join(dir_path, 'common', 'labyrinthPages.js')
  js_content = <<~JSCRIPT
    // Contains the list of all pages, that are ready to go.
    // There are other pages that are not ready to go, but are referenced in the code.
    // Those other pages will be ignored when the links are randomly generated via randomise.rb
    const labyrinthPages = [
    #{corridors_for_js.map { |p| "  \"../../#{p}\"," }.join("\n")}
    ];
  JSCRIPT
  FileUtils.mkdir_p(File.dirname(js_path))
  File.write(js_path, js_content)
  puts "Generated #{js_path}"

  # 2. Generate index.html
  template = File.read('template.html')

  corridor_links = corridor_dirs.map do |d|
    title = get_formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + "index.html"
    "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
  end.join("\n")

  room_links = room_dirs.map do |d|
    title = get_formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + "index.html"
    "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
  end.join("\n")

  index_content = template.gsub('{{CORRIDOR_LINKS}}', corridor_links)
  index_content.gsub!('{{ROOM_LINKS}}', room_links)

  File.write(File.join(dir_path, 'index.html'), index_content)
  puts "Generated #{File.join(dir_path, 'index.html')}"

  # Return the corridors for randomization mapping
  corridors_for_js
end

# 1. Housekeeping
puts "Housekeeping WIP directory..."
generate_dir_files(WIP_DIR)

puts "Housekeeping PRIVATE directory..."
corridors = generate_dir_files(SOURCE_DIR)

# 2. Create public directory (clean copy of private, excluding WIPs)
puts "Generating #{TARGET_DIR}..."
FileUtils.rm_rf(TARGET_DIR)
FileUtils.cp_r(SOURCE_DIR, TARGET_DIR)

# Remove any lingering WIP directories from public (if they were in private with .wip file)
Dir.glob(File.join(TARGET_DIR, '**/.wip')).each do |wip_file|
  wip_dir = File.dirname(wip_file)
  FileUtils.rm_rf(wip_dir)
  puts "Removed WIP corridor from public: #{wip_dir}"
end

# 3. Randomise links in public/
html_files = Dir.glob(File.join(TARGET_DIR, '**/*.html'))

html_files.each do |file|
  next unless File.exist?(file)
  content = File.read(file)
  relative_path = file.sub("#{TARGET_DIR}/", '')
  depth = relative_path.count('/')
  prefix = "../" * depth

  # Filter out current page to avoid self-linking
  possible_corridors = corridors.reject { |c| c == relative_path }
  possible_corridors = corridors.dup if possible_corridors.empty?
  buffer = possible_corridors.shuffle

  new_content = content.gsub(/['"][^'"]*todo\.html['"]/) do |match|
    quote = match[0]
    buffer = possible_corridors.shuffle if buffer.empty?
    random_corridor = buffer.pop
    "#{quote}#{prefix}#{random_corridor}#{quote}"
  end

  if content != new_content
    File.write(file, new_content)
    puts "Randomised links in #{file}"
  end
end

puts "Done!"
