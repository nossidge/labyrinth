require 'fileutils'
require 'json'
require 'yaml'
require 'time'

# Configuration
SOURCE_DIR = 'private'
TARGET_DIR = 'public'
TMP_PAGES_DIR = 'tmp/pages'
DEV_MODE = ARGV.include?('--dev')
LINK_SUFFIX = DEV_MODE ? 'index.html' : ''

# Load creation dates and full corridor metadata from corridors.yaml
def load_creation_dates
  data = YAML.load_file('corridors.yaml')
  dates = {}
  data['corridors'].each do |corridor|
    id = corridor['id']
    created = corridor['created']
    # Parse date string "yyyy-mm-dd hh:mm" or handle "Not yet created"
    if created && created != 'Not yet created'
      dates[id] = Time.strptime(created, '%Y-%m-%d %H:%M')
    else
      dates[id] = Time.at(0) # Earliest possible time for unpublished
    end
  end
  dates
end

def load_corridor_metadata
  data = YAML.load_file('corridors.yaml')
  metadata = {}
  data['corridors'].each do |corridor|
    id = corridor['id']
    metadata[id] = {
      'title' => corridor['title'],
      'created' => corridor['created'],
      'mobile' => corridor['mobile'],
    }
  end
  metadata
end

CREATION_DATES = load_creation_dates
CORRIDOR_METADATA = load_corridor_metadata

def formatted_title(dir_path)
  File.basename(dir_path).split('-').map(&:capitalize).join(' ')
end

def creation_date(dir_path)
  dir_name = File.basename(dir_path)
  CREATION_DATES[dir_name] || Time.at(0)
end

def generate_dir_files(dir_path)
  corridor_dirs = Dir.glob(File.join(dir_path, 'corridors', '*/')).sort_by { |d| creation_date(d) }
  room_dirs = Dir.glob(File.join(dir_path, 'rooms', '*/')).sort_by { |d| creation_date(d) }

  # Corridors for randomisation mapping
  corridors_for_js = corridor_dirs.map { |d| d.sub("#{dir_path}/", '') + LINK_SUFFIX }

  # 1. Generate common/labyrinth.js
  js_path = File.join(dir_path, 'common', 'labyrinth.js')

  # Build corridorsData array with metadata
  corridors_data_entries = corridor_dirs.map do |d|
    corridor_id = File.basename(d)
    metadata = CORRIDOR_METADATA[corridor_id] || { 'title' => formatted_title(d), 'created' => 'Unknown' }
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
    {
      id: corridor_id,
      title: metadata['title'],
      created: metadata['created'],
      url: "../../#{rel_path}",
      mobile: metadata['mobile'] || false,
    }
  end

  # Build JavaScript object literals for corridorsData
  corridors_data_js = corridors_data_entries.map do |entry|
    "  #{JSON.generate(entry)},"
  end.join("\n")

  js_content = File.read('template/labyrinth.js')
  js_content.gsub!(/^\s*'\{\{ CORRIDOR_DATA_ROWS \}\}'$/, corridors_data_js)

  FileUtils.mkdir_p(File.dirname(js_path))
  File.write(js_path, js_content)
  puts "Generated #{js_path}"

  old_js_path = File.join(dir_path, 'common', 'labyrinthPages.js')
  if File.exist?(old_js_path)
    FileUtils.rm_f(old_js_path)
    puts "Removed #{old_js_path}"
  end

  # 2. Generate index.html (internal list)
  template = File.read('template/list.html')

  corridor_links = corridor_dirs.map do |d|
    title = formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
    "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
  end.join("\n")

  room_links = room_dirs.map do |d|
    title = formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
    "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
  end.join("\n")

  index_content = template.gsub('{{CORRIDOR_LINKS}}', corridor_links)
  index_content.gsub!('{{ROOM_LINKS}}', room_links)

  File.write(File.join(dir_path, 'index.html'), index_content)
  puts "Generated #{File.join(dir_path, 'index.html')}"

  # Return the corridors for randomisation mapping
  corridors_for_js
end

# 1. Housekeeping
puts "Housekeeping PRIVATE directory..."
corridors = generate_dir_files(SOURCE_DIR)

# 1a. In DEV_MODE, append links to tmp/pages/*/corridors/* below the existing lists
def build_tmp_pages_sections
  return '' unless Dir.exist?(TMP_PAGES_DIR)

  sections = []
  Dir.glob(File.join(TMP_PAGES_DIR, '*/')).sort.each do |category_dir|
    category_name = File.basename(category_dir)
    corridors_dir = File.join(category_dir, 'corridors')
    next unless Dir.exist?(corridors_dir)

    corridor_dirs = Dir.glob(File.join(corridors_dir, '*/')).sort_by { |d| File.basename(d) }
    next if corridor_dirs.empty?

    header = category_name.split(/[-_]/).map(&:capitalize).join(' ')
    links = corridor_dirs.map do |d|
      title = formatted_title(d)
      # Path is relative to private/index.html
      rel_path = "../#{d}index.html"
      "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
    end.join("\n")

    sections << "  <div>\n    <h1>#{header}</h1>\n    <ol>\n#{links}\n    </ol>\n  </div>"
  end

  sections.join("\n")
end

if DEV_MODE
  tmp_sections = build_tmp_pages_sections
  unless tmp_sections.empty?
    private_index_path = File.join(SOURCE_DIR, 'index.html')
    private_index_content = File.read(private_index_path)
    private_index_content.sub!('</body>', "#{tmp_sections}\n</body>")
    File.write(private_index_path, private_index_content)
    puts "Added tmp/pages sections to #{private_index_path}"
  end
end

# 2. Create public directory (clean copy of private, minus todo.html and WIPs)
puts "Generating #{TARGET_DIR}..."
FileUtils.rm_rf(TARGET_DIR)
FileUtils.mkdir_p(TARGET_DIR)

Dir.each_child(SOURCE_DIR) do |child|
  next if child == 'todo.html'
  FileUtils.cp_r(File.join(SOURCE_DIR, child), File.join(TARGET_DIR, child))
end

# 3. Setup public entry points
puts "Setting up public entry points..."
FileUtils.mkdir_p(File.join(TARGET_DIR, 'assets'))
FileUtils.cp('assets/labyrinthus.png', File.join(TARGET_DIR, 'assets', 'labyrinthus.png'))

public_index_content = File.read('template/index.html')
current_date = Time.now.strftime('%Y-%m-%d')
total_pages = corridors.length

public_index_content.gsub!(/(<strong id="date-last-updated">).*?(<\/strong>)/m, "\\1\n          #{current_date}\n        \\2")
public_index_content.gsub!(/(<strong id="page-count">).*?(<\/strong>)/m, "\\1\n          #{total_pages}\n        \\2")

File.write(File.join(TARGET_DIR, 'index.html'), public_index_content)

FileUtils.mkdir_p(File.join(TARGET_DIR, 'random'))
FileUtils.cp('template/random.html', File.join(TARGET_DIR, 'random', 'index.html'))

puts "Done!"
