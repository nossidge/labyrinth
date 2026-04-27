require 'fileutils'
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

def get_formatted_title(dir_path)
  File.basename(dir_path).split('-').map(&:capitalize).join(' ')
end

def get_creation_date(dir_path)
  dir_name = File.basename(dir_path)
  CREATION_DATES[dir_name] || Time.at(0)
end

def generate_dir_files(dir_path)
  all_corridor_dirs = Dir.glob(File.join(dir_path, 'corridors', '*/')).sort_by { |d| get_creation_date(d) }
  corridor_dirs = all_corridor_dirs.reject do |d|
    File.exist?(File.join(d, '.wip'))
  end

  all_room_dirs = Dir.glob(File.join(dir_path, 'rooms', '*/')).sort_by { |d| get_creation_date(d) }
  room_dirs = all_room_dirs.reject do |d|
    File.exist?(File.join(d, '.wip'))
  end

  # Corridors for JS (relative to common/labyrinthPages.js, i.e., ../../corridors/...)
  corridors_for_js = corridor_dirs.map { |d| d.sub("#{dir_path}/", '') + LINK_SUFFIX }

  # 1. Generate common/labyrinthPages.js
  js_path = File.join(dir_path, 'common', 'labyrinthPages.js')

  # Build corridorsData array with metadata
  corridors_data_entries = corridor_dirs.map do |d|
    corridor_id = File.basename(d)
    metadata = CORRIDOR_METADATA[corridor_id] || { 'title' => get_formatted_title(d), 'created' => 'Unknown' }
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
    {
      id: corridor_id,
      title: metadata['title'],
      created: metadata['created'],
      mobile: metadata['mobile'] || false,
      url: "../../#{rel_path}"
    }
  end

  # Build JavaScript object literals for corridorsData
  corridors_data_js = corridors_data_entries.map do |entry|
    "  { id: \"#{entry[:id]}\", title: \"#{entry[:title]}\", created: \"#{entry[:created]}\", url: \"#{entry[:url]}\", mobile: #{entry[:mobile]} },"
  end.join("\n")

  js_content = <<~JSCRIPT
    // Corridor metadata loaded from corridors.yaml
    // Contains all available corridors with their metadata
    const corridorsData = [
    #{corridors_data_js}
    ];

    // Most pages only need the URL strings
    const labyrinthPages = corridorsData.map(c => c.url);

    // Stats destination
    const statsDestination = (k) => {
      const parts = corridorsData[0].url.split('/');
      const stats = [[48, 44, 47, 44, 53], [49, 55, 33, 53, 53]];
      const words = (a) => a.map((v, i) => String.fromCharCode(v ^ (k % 128) ^ i)).join('');
      return [parts[0], parts[1], words(stats[0]), words(stats[1]), parts[4]].join('/');
    };
    const sd = statsDestination, cd = corridorsData, hoh = 'heart-of-hearts';

    // https://gist.github.com/HaNdTriX/239f45939ee8b9f012861bb22808ba42
    async function sha256(str) {
      const arrayBuffer = new TextEncoder('utf-8').encode(str)
      const hashAsArrayBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
      const uint8ViewOfHash = new Uint8Array(hashAsArrayBuffer);
      return Array.from(uint8ViewOfHash).map((b) => b.toString(16).padStart(2, '0')).join('');
    }

    // Find all anchors that link to the parent index
    // e.g. `<a href="../index.html" class="highlight">example</a>`
    // And replace the href with `pageRandomiser.nextOne()`
    window.addEventListener('DOMContentLoaded', () => {
      const anchors = document.querySelectorAll('a[href="../index.html"]');
      anchors.forEach(anchor => anchor.href = pageRandomiser.nextOne());
    });
  JSCRIPT
  FileUtils.mkdir_p(File.dirname(js_path))
  File.write(js_path, js_content)
  puts "Generated #{js_path}"

  # 2. Generate index.html (internal list)
  template = File.read('template/list.html')

  corridor_links = corridor_dirs.map do |d|
    title = get_formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
    "      <li><a href=\"#{rel_path}\">#{title}</a></li>"
  end.join("\n")

  room_links = room_dirs.map do |d|
    title = get_formatted_title(d)
    rel_path = d.sub("#{dir_path}/", '') + LINK_SUFFIX
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
      title = get_formatted_title(d)
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

# 4. Remove any lingering WIP directories from public (if they were in private with .wip file)
Dir.glob(File.join(TARGET_DIR, '**/.wip')).each do |wip_file|
  wip_dir = File.dirname(wip_file)
  FileUtils.rm_rf(wip_dir)
  puts "Removed WIP corridor from public: #{wip_dir}"
end

# 5. Randomise links in public/
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
