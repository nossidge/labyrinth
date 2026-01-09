require 'fileutils'

# Configuration
SOURCE_DIR = 'labyrinth'
TARGET_DIR = 'final'
COMMON_DIR = File.join(SOURCE_DIR, 'common')
PAGES_JS = File.join(COMMON_DIR, 'labyrinthPages.js')

# 1. Gather all corridors, excluding those with .wip files
all_corridor_dirs = Dir.glob(File.join(SOURCE_DIR, 'corridors', '*/'))
active_corridors = all_corridor_dirs.reject do |dir|
  File.exist?(File.join(dir, '.wip'))
end

corridors = active_corridors.map do |path|
  "#{path.sub("#{SOURCE_DIR}/", '')}index.html"
end

puts "Found #{corridors.length} active corridors (skipped #{all_corridor_dirs.length - active_corridors.length} WIPs)."

# 2. Generate labyrinthPages.js
# We'll use the relative path from a corridor page (../../) as requested by the user.
js_content = <<~JSCRIPT
  // Contains the list of all pages, that are ready to go.
  // There are other pages that are not ready to go, but are referenced in the code.
  // Those other pages will be ignored when the links are randomly generated via randomise.rb
  const labyrinthPages = [
  #{corridors.map { |c| "  \"../../#{c}\"," }.join("\n")}
  ];
JSCRIPT

File.write(PAGES_JS, js_content)
puts "Generated #{PAGES_JS}"

# 3. Create final directory
FileUtils.rm_rf(TARGET_DIR)
FileUtils.cp_r(SOURCE_DIR, TARGET_DIR)

# Remove WIP directories from final/
skipped_corridors = []
all_corridor_dirs.each do |dir|
  if File.exist?(File.join(dir, '.wip'))
    wip_name = dir.sub("#{SOURCE_DIR}/corridors/", '')
    skipped_corridors << wip_name
    wip_target = File.join(TARGET_DIR, dir.sub("#{SOURCE_DIR}/", ''))
    FileUtils.rm_rf(wip_target)
    puts "Removed WIP corridor: #{wip_target}"
  end
end

# Remove WIP links from final/index.html
final_index = File.join(TARGET_DIR, 'index.html')
if File.exist?(final_index)
  index_content = File.read(final_index)
  skipped_corridors.each do |wip_path|
    wip_name = wip_path.chomp('/')
    # Match the <li> line that contains the WIP corridor link
    index_content.gsub!(/^\s*<li>.*corridors\/#{Regexp.escape(wip_name)}\/.*<\/li>.*?\n/, '')
  end
  File.write(final_index, index_content)
  puts "Cleaned up WIP links in #{final_index}"
end

puts "Copied #{SOURCE_DIR} to #{TARGET_DIR}"

# 4. Randomise links in final/
# We need to find all HTML files in final/
html_files = Dir.glob(File.join(TARGET_DIR, '**/*.html'))

html_files.each do |file|
  next unless File.exist?(file)
  content = File.read(file)

  # Determine the depth to adjust the relative path
  relative_path = file.sub("#{TARGET_DIR}/", '')
  depth = relative_path.count('/')

  prefix = "../" * depth

  # Replace todo.html links
  new_content = content.gsub(/['"][^'"]*todo\.html['"]/) do |match|
    quote = match[0]
    # Filter out current corridor to avoid self-linking
    current_corridor = relative_path.split('/')[1] # e.g., "ufo"
    possible_corridors = corridors.reject { |c| c.include?(current_corridor) }

    random_corridor = possible_corridors.sample || corridors.sample
    "#{quote}#{prefix}#{random_corridor}#{quote}"
  end

  if content != new_content
    File.write(file, new_content)
    puts "Randomised links in #{file}"
  end
end

puts "Done!"
