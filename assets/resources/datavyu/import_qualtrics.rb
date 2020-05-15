## Parameters
qualtrics_folder = '~/Desktop/Qualtrics'
datavyu_folder = '~/Desktop/Datavyu'

targetsex_map = { 'g' => 'f', 'w' => 'f', 'b' => 'm', 'm' => 'm' }

stereotype_map = { %w[construction cars football superhero firefighter tools
  worms trucks] => 'm',
  %w[makeup laundry princess flowers ballet baby dolls nails] => 'f'
}

## Body
require 'Datavyu_API.rb'
require 'csv'

qualtrics_path = File.expand_path(qualtrics_folder)
qualtrics_files = Dir.chdir(qualtrics_path) { Dir.glob('*.csv') }

datavyu_path = File.expand_path(datavyu_folder)
datavyu_files = Dir.chdir(datavyu_path) { Dir.glob('*.opf') }

qualtrics_files.sort.each do |qfile|

  puts "Convering qualtrics file #{qfile}..."

  # get the corresponding datavyu file for the current qualtrics csv
  dfile = datavyu_files.select{ |f| f.include?(qfile.split('_')[0]) }.first

  $db, $pj = load_db(File.join(datavyu_path, dfile))

  # fetch the task column
  task = get_column('task')

  # initialize trial column for storing qualtrics events and times
  trial = new_column('trial', %w[trial targetsex_mfn stereotype_sex])

  # read qualtrics table from csv file
  qtable = CSV.read(File.join(qualtrics_path, qfile))
  # extract the header and data from the table
  header = qtable[0]
  data = qtable[-1]

  # get onset of task in seconds for qualtrics data
  qt0 = data[header.index('intro_onset')].to_i

  # get onset of task in milliseconds for datavyu spreadsheet
  dt0 = task.cells.select{ |c| c.task == 'p' }.first.onset.to_i

  header_trial = header.select{ |x| x.include?('onset') || x.include?('offset') }
  header_trial.reject!{ |x| x.include?('intro') || x.include?('end') }

  trial_code = header_trial.map{ |x| x.split('_')[0] }
  trial_code = trial_code.uniq

  trial_code.each do |tc|

    trial_onset = header_trial.select{ |x| x.include?(tc) && x.include?('onset') }
    trial_offset = header_trial.select{ |x| x.include?(tc) && x.include?('offset') }

    trial_onset.reject!{ |x| data[header.index(x)].nil? }
    trial_offset.reject!{ |x| data[header.index(x)].nil? }

    trial_onset.each_with_index{ |x,i|

      dq_onset = data[header.index(x)].to_i - qt0
      dq_offset = data[header.index(trial_offset[i])].to_i - qt0

      ncell = trial.new_cell()
      ncell.onset = dt0 + dq_onset*1000
      ncell.offset = dt0 + dq_offset*1000 - 1

      ncell.trial = tc
      ncell.targetsex_mfn = targetsex_map[trial_onset.first.split('_')[1]]
      ncell.stereotype_sex = stereotype_map[stereotype_map.keys.select{
        |k| k.include?(tc) }.first]

    }
  end

  set_column('trial', trial)

  save_db(File.join(datavyu_path, dfile))
end
