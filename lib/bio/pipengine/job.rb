module Bio
	module Pipengine
		
		class Job
			
			attr_accessor :name, :cpus, :resources, :command_line, :local, :samples_groups, :samples_obj
			def initialize(name)
				@name = generate_uuid + "-" + name
				@command_line = []
				@resources = {}
				@cpus = 1
			end

			def add_resources(resources)
				self.resources.merge! resources
			end

			def output
				self.resources["output"]
			end

			def add_step(step,sample)
				
				# setting job working directory
				working_dir = ""	
				if self.local 
					working_dir = self.local+"/"+self.name
				else
					working_dir = self.output
					if step.is_group?
						working_dir += "/#{step.name}"
					else
						working_dir += "/#{sample.name}/#{step.name}"
					end
				end

				# set job cpus number to the higher step cpus (this in case of multiple steps)
				self.cpus = step.cpus if step.cpus > self.cpus
				# adding job working directory
				self.command_line << "mkdir -p #{working_dir}"
				self.command_line << "cd #{working_dir}"
				
				if step.run.kind_of? Array
					step.run.each do |cmd|
						self.command_line << generate_cmd_line(cmd,sample,step)	
					end
				else
					self.command_line << generate_cmd_line(step.run,sample,step)
				end
				
				if self.local
					final_output = ""
					if step.is_group?
						final_output = self.output+"/#{step.name}"
					else
						final_output = self.output+"/#{sample.name}/#{step.name}"
					end
					self.command_line << "mkdir -p #{final_output}"
					self.command_line << "cp -r #{working_dir}/* #{final_output}"
					self.command_line << "rm -fr #{working_dir}"
				end

			end

			def to_pbs(options)
				header = []
				header << "#!/bin/bash"
				header << "#PBS -N #{self.name}"
				header << "#PBS -q #{options[:pbs_queue]}" if options[:pbs_queue]
				header << "#PBS -l ncpus=#{self.cpus}"
				if options[:pbs_opts]
					options[:pbs_opts].each do |opt|
						header << "#PBS -l #{opt}"
					end
				end
				filename = self.name+".pbs"
				File.open(filename,"w") do |file|
					file.write(header.join("\n")+"\n")
					file.write(self.command_line.join("\n")+"\n")
				end
				return filename
			end

		private
			
			def generate_uuid
				UUID.new.generate.split("-").first
			end

			def generate_cmd_line(cmd,sample,step)
				if step.is_group?
					set_groups_cmd(step,self.samples_groups)
					cmd = sub_groups(cmd,step)
				else
					cmd = sub_placeholders(cmd,sample,step)
				end
				return cmd
			end
			
			def sub_placeholders(cmd,sample,step=nil)	
				tmp_cmd = cmd.gsub(/<sample>/,sample.name)
				tmp_cmd = tmp_cmd.gsub(/<sample_path>/,sample.path.join(" "))
				
				# for resourcers and cpus
				tmp_cmd = sub_resources_and_cpu(tmp_cmd,step)
				
				# for placeholders like <mapping/sample>
				tmp_cmd.scan(/<(\S+)\/sample>/).map {|e| e.first}.each do |input_folder|
					tmp_cmd = tmp_cmd.gsub!(/<#{input_folder}\/sample>/,self.output+"/"+sample.name+"/"+input_folder+"/"+sample.name)
				end
				
				# for placeholders like <mapping/>
				tmp_cmd.scan(/<(\S+)\/>/).map {|e| e.first}.each do |input_folder|
					tmp_cmd = tmp_cmd.gsub(/<#{input_folder}\/>/,self.output+"/"+sample.name+"/"+input_folder+"/")
				end
				return tmp_cmd
			end

			def sub_resources_and_cpu(cmd,step)	
				# for all resources tags like <gtf> <index> <genome> <bwa> etc.
				self.resources.each_key do |r|
					cmd.gsub!(/<#{r}>/,self.resources[r])
				end
				# set number of cpus for this command line
				cmd.gsub!(/<cpu>/,step.cpus.to_s) unless step.nil?
				return cmd
			end

			def set_groups_cmd(step,sample_groups)
				if step.groups_def.kind_of? Array
					step.groups_cmd = []
					step.groups_def.each do |g_def|
						step.groups_cmd << generate_groups_cmd(g_def,sample_groups)
					end
				else
					step.groups_cmd = generate_groups_cmd(step.groups_def,sample_groups)
				end
			end

			def sub_groups(cmd,step)
				cmd = sub_resources_and_cpu(cmd,step)
				if step.groups_cmd.kind_of? Array
					step.groups_cmd.each_with_index do |g,index|
						cmd.gsub!(/<groups#{index+1}>/,g)
					end
				else
					cmd.gsub!(/<groups>/,step.groups_cmd)
				end
				return cmd
			end

			def generate_groups_cmd(group_def,sample_groups)
				group_cmd = []	
				sample_groups.each do |sample_name|
					if sample_name.include? ","
						group_cmd << split_and_sub(",",group_def,sample_name)
					elsif sample_name.include? ";"
						group_cmd << split_and_sub(";",group_def,sample_name)
					else
						group_cmd << sub_placeholders(group_def,self.samples_obj[sample_name])
					end
				end
				return group_cmd.join("\s")
			end

			def split_and_sub(sep,group_def,group)	
				cmd_line = []
				group.split(sep).each do |sample_name|
					cmd_line << sub_placeholders(group_def,self.samples_obj[sample_name])
				end
				cmd_line.join(sep)
			end

		end
	end
end

