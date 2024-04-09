## Parameters
# Populates trial column with qualtrics data for all datavyu files in folder
# As of 09/27/2023, script aligns the offset of consent in DV to consent_offset in qualtrics

# Folder with datavyu files
datavyu_folder = '~/Desktop/Datavyu' + '/'
# Folder with master qualtrics csv file
qualtrics_folder = '~/Desktop/Qualtrics' + '/'
# Folder to export new Datavyu file to
output_folder = '~/Desktop/Output' + '/'

## Body
require 'Datavyu_API.rb'
require 'csv'

# Expand the qualtrics file apth, load the file
qualtrics_path = File.expand_path(qualtrics_folder)
# assumes there is just one master csv file in folder (takes first)
qfile = Dir.chdir(qualtrics_path) { Dir.glob('*.csv') }.first

# Expand the output path, make the folder if it doesn't exist
output_path = File.expand_path(output_folder)
Dir.mkdir(output_path) unless File.exists?(output_path)

# Expand the DV path, get list of all files
datavyu_path = File.expand_path(datavyu_folder)
dvfiles = Dir.chdir(datavyu_path) {Dir.glob('*.opf') }

# read qualtrics table from csv file
qtable = CSV.read(File.join(qualtrics_path, qfile), :row_sep => :auto)

# Loop over the DV files
for dvfile in dvfiles  # load the current datavyu project
  $db, pj = load_db(File.join(datavyu_path, dvfile))
  # fetch the task column
  if !(get_column_list.include?('task'))
    puts "WARNING! No task column"
    puts "Skipping #{dvfile}"
    next
  elsif get_column_list.include?('task')
    task = get_column('task')
    if task.cells.length == 0
      puts "WARNING! Task column has no cells coded"
      puts "Skipping #{dvfile}"
      next
    end
  end
  ## get the task column
  task_code = task.cells.first.arglist.first # get the first argument of the first cell in the task column
  
  # Get the task cell coded as "c"
  flag = false # flag to check if there is a cell coded p
  c_cell = nil # holder to store the "c" cell when we find it
  
  # First check if there's a task cell coded c
  for cell in task.cells
    if cell.get_code(task_code) == 'c'
      # If there is a cell coded p, set the flag to true & save the p cell for later
      flag = true
      c_cell = cell
    end
  end
  # If there's no p cell and the flag is still false, give an error and set the task on set as a arbitrary number
  if flag == false
    puts "WARNING! No cell with code <p> found in task column. Automatically setting task onset to 1000 ms."
    dv_taskon = 1000
    # If there is a c cell, get it's offset
  else
    # get onset of task in milliseconds for datavyu spreadsheet
    dv_taskon = c_cell.offset.to_i
    puts "Consent offset is #{dv_taskon} ms in #{dvfile}"
  end
  
  # Create trial column for storing qualtrics events and times
  trial = createColumn('trial', "trial") # First 'trial' is the column name, second is the name of the argument
  
  # Now get the qualtrics data
  # Get the id from the Datavyu filename; assumes id is all the characters before first underscore of filename
  id = dvfile.split('_')[0]
  # extract the header and data from the first row of the table
  header = qtable[0]
  # Find what index (aka which column) is the ID column in qualtrics file
  id_index = header.index('ID')
  
  # loop over rows of data skipping the header and find line for current id
  for line in qtable[1..-1]
    # If the value in the ID column of the current row is nil/empty, skip this line
    if line[id_index].nil?
      next
    end
    # If the value in the ID column of the current row matches the ID of the current Datavyu file, that line is the data to import
    if line[id_index] == id
      # set data equal to line for current id (i.e., load the current line into "data", where we'll get all the info to import)
      data = line
    end
  end
  
  # get onset of task in seconds for qualtrics data
  qual_taskon = data[header.index('consent_offset')].to_i
  # get a list of all the qualtrics column names that include "_onset" or "_offset" that we'll import data from
  header_trial = []
  for col_name in header
    if col_name.include?('onset') or col_name.include?('offset')
      # exclude columns with "intro" or "end" in the name
      if not (col_name.include?('intro') or col_name.include?('end'))
        header_trial << col_name
      end
    end
  end
  
  # Get the just the first part of each column name (without the _onset part)
  trial_code = []
  # loop over the qualtrics names we selected before
  for col_name in header_trial
    # split off the "_onset" and add the remaining name to trial_code for later
    trial_code << col_name.split('_')[0]
  end
  # just take unique values to avoid repeats, since lots of variables have an onset & an offset column
  trial_code = trial_code.uniq
  
  # loop over the names in the trial_code list
  for tc in trial_code
    # get onset and offset of trial
    
    # create arrays to hold all the names of all the onset columns & offset columns
    trial_onset = []
    trial_offset = []
    
    # loop over the qualtrics column names, to get the names of the onset & offset columns
    for col_name in header_trial
      # if the name is in our list of columns to import & includes "onset", add it to the list of onset columns
      if col_name.include?(tc) and col_name.include?('onset')
        # if there's no value for that column in this line of data, throw it out of the onset & offset lists
        if not data[header.index(col_name)].nil?
          trial_onset << col_name
        end
      end
      # if the name is in our list of columns to import & includes "offset", add it to the list of offset columns
      if col_name.include?(tc) and col_name.include?('offset')
        # if there's no value for that column in this line of data, throw it out of the onset & offset lists
        if not data[header.index(col_name)].nil?
          trial_offset << col_name
        end
      end
    end
    
    # create cell in column trial for each trial
    for i in 0...trial_onset.length
      x = trial_onset[i]
      
      puts "Populating #{dvfile} trial column with cell for #{tc}..."
      
      # get onset relative to task start 
      # get the actual onset from data for this entry in trial_onset, minus the qualtrics onset
      dq_onset = data[header.index(x)].to_i - qual_taskon
      
      # get the offset relative to task start
      if not trial_offset[i].nil? # if the header isn't empty
        # get the actual offset from data for this entry in trial_offset, minus the qualtrics onset
        dq_offset = data[header.index(trial_offset[i])].to_i - qual_taskon
      else
        dq_offset = dq_onset
      end
      
      # create a new cell
      ncell = trial.new_cell()
      
      # if the onset goes negative, set the cell's times to 0 instead
      if (dv_taskon + dq_onset * 1000.0) <0
        ncell.onset = 0
        ncell.offset = 0
      else
        # if the times don't go negative, set as the Datavyu task onset + the qualtrics time
        if dq_onset != dq_offset # if there's both osnet & offset, set both
          ncell.onset = dv_taskon + dq_onset * 1000
          ncell.offset = dv_taskon + dq_offset * 1000 - 1
        else # make it a point cell if no offset info
          ncell.onset = dv_taskon + dq_onset * 1000
          ncell.offset = dv_taskon + dq_onset * 1000
        end
      end
      
      
      # fill in the trial code into the new cell
      ncell.trial = tc
      
    end
    
    # set the column back to the Datavyu file 
    set_column('trial', trial)
    
    # save the file
    puts "Saving #{dvfile} to reflect changes"
    save_db(File.join(output_path, dvfile))
  end
end