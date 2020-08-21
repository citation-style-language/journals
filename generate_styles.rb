#! /usr/bin/ruby
# encoding: utf-8

# for FileUtils.mkdir_p and .cp_r
require 'fileutils'
# for script options
require 'optparse'
# for publishers.json
require 'json'

# converts style title to style ID
def title_to_styleID(title)
  styleID = title.downcase

  # remove content between last set of parentheses
  styleID = styleID.reverse.sub(/\).*?\( /, '').reverse

  # remove content between last set of square brackets
  styleID = styleID.reverse.sub(/\].*?\[ /, '').reverse

  # punctuation to eliminate
  styleID.delete!('?')
  styleID.delete!('!')
  styleID.delete!('’')
  styleID.delete!('(')
  styleID.delete!(')')
  styleID.delete!('\'')
  styleID.delete!('|')
  styleID.delete!('"')

  # punctuation to replace
  styleID.tr!(' ', '-')
  styleID.tr!('–', '-')
  styleID.tr!(',', '-')
  styleID.tr!(':', '-')
  styleID.tr!('.', '-')
  styleID.tr!('/', '-')
  styleID.gsub!('&', '-and-')
  styleID.tr!('+', '-')
  styleID.gsub!(/-{2,}/, '-')

  # remove hyphens at ends
  styleID.gsub!(/^-/, '')
  styleID.gsub!(/-$/, '')

  # remove diacritics
  styleID.gsub!(/á/i, 'a')
  styleID.gsub!(/à/i, 'a')
  styleID.gsub!(/ä/i, 'a')
  styleID.gsub!(/ã/i, 'a')
  styleID.gsub!(/ą/i, 'a')
  styleID.gsub!(/č/i, 'c')
  styleID.gsub!(/ç/i, 'c')
  styleID.gsub!(/é/i, 'e')
  styleID.gsub!(/è/i, 'e')
  styleID.gsub!(/ê/i, 'e')
  styleID.gsub!(/ë/i, 'e')
  styleID.gsub!(/ę/i, 'e')
  styleID.gsub!(/í/i, 'i')
  styleID.gsub!(/ń/i, 'n')
  styleID.gsub!(/ñ/i, 'n')
  styleID.gsub!(/ó/i, 'o')
  styleID.gsub!(/ö/i, 'o')
  styleID.gsub!(/ß/i, 'ss')
  styleID.gsub!(/ü/i, 'u')

  styleID
end

options = { directory: nil, sync: false }

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: generate_styles.rb [options]'
  opts.on('-d', '--dir directory', 'Limit script to specified data subdirectory (e.g., "asm")') do |directory|
    options[:directory] = directory
  end

  opts.on('-s', '--sync [LIMITED_TO]', %w(additions deletions modifications),
          'Sync style changes to "styles" repo, optionally limited to: "[a]dditions", "[d]eletions", "[m]odifications"') do |sync_type|
    options[:sync] = true
    options[:sync_type] = sync_type || ''
  end

  opts.on('-f', '--force', 'Force sync (by default, styles that only differ in their timestamp are not updated)') do |_force_sync|
    options[:force_sync] = true
  end

  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit
  end
end

parser.parse!

# Print current directory
This_script_dir = File.dirname(File.expand_path(__FILE__))
$stderr.puts "Script:\t#{This_script_dir}"

# Read publishers.json
begin
  publishers = JSON.parse(File.read("#{This_script_dir}/publishers.json"))
rescue
  abort("Error parsing file \"publishers.json\" (make sure file is valid JSON)")
end

# Determine directories to parse
data_subdir_paths = []
if !options[:directory].nil?
  if File.directory? "#{This_script_dir}/#{options[:directory]}"
    data_subdir_paths.push("#{options[:directory]}")
  else
    $stderr.puts "WARNING: subdirectory '#{options[:directory]}' does not exist"
    abort 'Failed'
  end
else
  Dir.foreach(This_script_dir) do |data_subdir|
    if File.file? "#{This_script_dir}/#{data_subdir}/_template.csl"
      data_subdir_paths.push(data_subdir)
    end
  end
end

# determine whether styles can be synced
sync_styles = false
if options[:sync] == true

  # check presence style dependents folder
  Dependent_dir_path = File.expand_path('../styles/dependent', This_script_dir)
  if File.exist? Dependent_dir_path
    sync_styles = true

    do_additions = false
    do_deletions = false
    do_modifications = false

    case options[:sync_type]
    when 'additions'
      do_additions = true
    when 'deletions'
      do_deletions = true
    when 'modifications'
      do_modifications = true
    else
      do_additions = true
      do_deletions = true
      do_modifications = true
    end

    do_force_sync = false
    do_force_sync = true if options[:force_sync] == true

    deleted_styles = 0
    copied_styles = 0
  else
    $stderr.puts "WARNING: Can't sync styles. Target directory not found at '#{Dependent_dir_path}'"
    abort 'Failed'
  end
end

# start with new empty style directory
generated_style_dir_path = "#{This_script_dir}/_dependent"
`rm -R '#{generated_style_dir_path}'` if File.exist? generated_style_dir_path
$stderr.puts "Output:\t#{generated_style_dir_path}"
$stderr.puts "\n"
$stderr.puts 'Generating styles...'
FileUtils.mkdir_p generated_style_dir_path

# keep track of all generated styles
identifiers_master_list = []

# we can now iterate over each of the data subdirs
total_count_created_styles = 0
data_subdir_paths.each do |data_subdir|
  # skip invalid entries
  next if data_subdir =~ /^\./
  data_subdir_path = "#{This_script_dir}/#{data_subdir}"
  template_path = "#{data_subdir_path}/_template.csl"
  journals_path = "#{data_subdir_path}/_journals.tab"
  skip_path     = "#{data_subdir_path}/_skip.txt"
  rename_path   = "#{data_subdir_path}/_rename.tab"
  extra_path    = "#{data_subdir_path}/_extra.tab"
  all_good = true
  [template_path, journals_path].each do |file_to_check|
    next if File.exist? file_to_check
    $stderr.puts "WARNING for '#{data_subdir}': missing file at path '#{file_to_check}'"
    all_good = false
  end
  unless all_good
    $stderr.puts "WARNING for '#{data_subdir}': cannot generate styles from directory"
    next
  end

  # hashes of hashes that will contain all the styles to generate
  styles = {}

  # load data into strings
  template = File.read(template_path)
  journals = File.read(journals_path).split(/\n/)
  skipped_journals = []
  skipped_journals = File.read(skip_path).split(/\n/) if File.exist? skip_path
  renamed_journals = []
  renamed_journals = File.read(rename_path).split(/\n/) if File.exist? rename_path
  extra_journals = []
  extra_journals = File.read(extra_path).split(/\n/) if File.exist? extra_path

  # combine journals and extra_journals, and remove header row from latter
  journals.concat(extra_journals.drop(1))

  # parse renamed_journals file
  old_and_new_names = {}
  renamed_journals.each do |renamed_journals_line|
    fields = renamed_journals_line.split(/\t/)
    old_and_new_names[fields[0]] = fields[1] if fields.length == 2
  end

  xml_comment = "generated from \"#{data_subdir}\" metadata at https://github.com/citation-style-language/journals"
  if publishers.key?(data_subdir)
    xml_comment = publishers["#{data_subdir}"] + ", " + xml_comment
  else
    $stderr.puts "WARNING: #{data_subdir} not listed in publishers.json"
  end

  # iterate over each journal
  header_info = []

  # load all the info from the tab-delimited info file
  count_created_styles = 0
  count_skipped_styles = 0
  count_overwritten_styles = 0

  # keep track of file names
  identifiers = []
  overwritten_styles = []

  journals.each do |journal_line|
    # each line contains tab-delimited fields
    fields = journal_line.split(/\t/)
    count_fields = fields.length

    # trim fields
    fields.each(&:strip!)

    # first line = the header
    if header_info.length == 0
      header_info = fields
      next
    end

    # sanity check
    if (count_fields != header_info.length)
      $stderr.puts "WARNING: journal info has the wrong number of fields (#{fields.join(', ')})"
      next
    end

    # create hash from the field values
    field_values = {}
    (0..count_fields - 1).each do |field_index|
      field_name = header_info[field_index].upcase
      field_values[field_name] = fields[field_index]
    end

    # more sanity check
    mandatory_fields = ['TITLE']
    fields_all_good = true
    mandatory_fields.each do |field_name_to_check|
      next if field_values.key? field_name_to_check and field_values[field_name_to_check].length > 0
      fields_all_good = false
      $stderr.puts "WARNING: journal info is missing field '#{field_name_to_check}': (#{fields.join(', ')})"
    end
    next unless fields_all_good

    # keep track of initial value of title to compare to the skip list
    initial_title = field_values['TITLE']

    identifier = title_to_styleID(field_values['TITLE'])

    # remove abbreviation in parenthesis that sometimes follow a title
    # Only remove last match, per http://stackoverflow.com/a/3185179/1712389
    field_values['TITLE'] = field_values['TITLE'].reverse.sub(/\).*?\( /, '').reverse

    # replace en-dashes in title by hyphens
    field_values['TITLE'] = field_values['TITLE'].tr('–', '-')
    
    # replace curly apostrophes in title by straight apostrophes
    field_values['TITLE'] = field_values['TITLE'].tr('’', "'")

    # convert square brackets to parentheses in title
    field_values['TITLE'] = field_values['TITLE'].tr('[', '(')
    field_values['TITLE'] = field_values['TITLE'].tr(']', ')')

    %w(TITLE TITLESHORT DOCUMENTATION).each do |key|
      if field_values.key?(key)
        field_values[key] = field_values[key].gsub('&', '&amp;') # XML escape
      end
    end

    field_values['XML-COMMENT'] = xml_comment

    # replace identifier if in renamed_journals file
    if old_and_new_names.key?(identifier)
      identifier = old_and_new_names[identifier]
    end

    field_values['IDENTIFIER'] = identifier

    # excluded journal?
    if skipped_journals.include?(initial_title) or skipped_journals.include?(identifier)
      # $stderr.puts "excluded journal: #{title}"
      count_skipped_styles += 1
      next
    end

    # count identifier if unique in dataset
    if identifiers.include?(identifier)
      count_overwritten_styles += 1
      overwritten_styles.push(identifier)
    else
      identifiers.push(identifier)
      count_created_styles += 1
    end

    # create style xml by replacing fields in the template
    style_xml = "#{template}"
    field_values.each do |name, value|
      placeholder = "##{name}#"
      
      #delete accepted placeholders ("x", "X", space)
      value.sub!(/^(x|\s)$/i, '')
      
      if value.length > 0
        # the value is valid --> replace the corresponding placeholder in the template
        style_xml.gsub! placeholder, value
      else
        # the value is empty --> remove the entire line from the template
        style_xml.gsub! /^.*#{placeholder}.*$\n/, ''
      end
    end

    # check if identifier have been generated in previous datasets
    if !identifiers_master_list.include?(identifier)
      # save file
      style_path = "#{generated_style_dir_path}/#{identifier}.csl"
      File.open(style_path, 'w') { |fileio| fileio.write style_xml }
    else
      $stderr.puts "Warning: skipped \"#{identifier}\" in #{data_subdir} (not unique)"
    end
  end

  identifiers_master_list += identifiers

  if sync_styles == true
    old_identifiers = []

    # legacy XML comment format
    old_xml_comment = "Generated with https://github.com/citation-style-language/utilities/tree/master/generate_dependent_styles/data/#{data_subdir}"

    # end of the current XML comment format (don't match against publisher description)
    xml_comment_tail = ", generated from \"#{data_subdir}\" metadata at https://github.com/citation-style-language/journals"

    dependents_path = "#{Dependent_dir_path}/*.csl"
    # check each dependent style for XML comment (field_values['XML-COMMENT'])
    Dir.glob(dependents_path) do |dependent_path|
      # delete dependent style if generated from current data subdirectory
      dependent = File.readlines(dependent_path)
      # Need `#{Regexp.escape(xml_comment)}` to escape possible parentheses in publisher names
      if (dependent.grep(/<!-- #{old_xml_comment} -->/).size > 0) or (dependent.grep(/<!-- (.*)#{Regexp.escape(xml_comment)} -->/).size > 0)
        old_identifier = File.basename(dependent_path, '.csl')
        old_identifiers.push(old_identifier)

        if do_deletions and !identifiers.include?(old_identifier)
          File.delete(dependent_path)
          deleted_styles += 1
        end
      end
    end

    # copy generated styles into dependents folder
    identifiers.each do |new_identifier|
      new_style_path = "#{generated_style_dir_path}/#{new_identifier}.csl"

      write = false
      if do_additions and !old_identifiers.include?(new_identifier)
        write = true
      elsif do_modifications and old_identifiers.include?(new_identifier)
        if do_force_sync == true
          write = true
        else
          # read old and new style
          old_style_path = "#{Dependent_dir_path}/#{new_identifier}.csl"
          old_style = File.read(old_style_path)
          new_style = File.read(new_style_path)

          # remove xml comment(s)
          xml_comment_regex = Regexp.new("<!--(.+)-->")
          new_style.sub!(xml_comment_regex, '<!-- -->')
          old_style.sub!(xml_comment_regex, '<!-- -->')
          
          # remove timestamp
          timestamp_regex = Regexp.new("<updated>(.+)<\/updated>")
          new_style.sub!(timestamp_regex, '<updated/>')
          old_style.sub!(timestamp_regex, '<updated/>')

          # compare modified old and new style, only overwrite if styles still differ
          write = true unless new_style.eql? old_style
        end
      end

      if write
        FileUtils.cp_r(new_style_path, "#{Dependent_dir_path}", remove_destination: true)
        copied_styles += 1
      end
    end

  end

  print "Generated #{count_created_styles}\t"
  if count_skipped_styles == 0
    print "\t\t"
  else
    print "Skipped #{count_skipped_styles}\t"
  end
  if count_overwritten_styles == 0
    print "\t\t"
  else
    print "Overwrote #{count_overwritten_styles}\t"
  end
  print "#{data_subdir}\n"
  $stdout.flush

  overwritten_styles.each do |overwritten_style|
    $stderr.puts "Overwrote: #{overwritten_style}"
  end

  total_count_created_styles += count_created_styles
end

if sync_styles == true
  $stderr.puts "Deleted #{deleted_styles} styles from #{Dependent_dir_path}"
  $stderr.puts "Copied #{copied_styles} styles to #{Dependent_dir_path}"
end

$stderr.puts "\nDone! #{total_count_created_styles} dependent CSL styles generated."
