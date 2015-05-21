require 'csv'
require 'active_support'


  desc 'links a chain of rake tasks to setup a project, groups, and subjects'

    # Given a project key (aka name/title), returns the Project instance from the db:
    def project_for_key(key)

      # project_file_path = Rails.root.join('project', key, 'project.json')
      # project_hash = JSON.parse File.read(project_file_path)

      project = Project.find_by key: key
      project
    end

    task :project_setup, [:project_key] => :environment do |task, args|
      project_key = args[:project_key]
      subjects_dir = Rails.root.join('project', project_key, 'subjects')

      Rake::Task['load_groups'].invoke(project_key)
    end

    task :load_groups, [:project_key] => :environment do |task, args|
      project_key = args[:project_key]
      subjects_dir = Rails.root.join('project', project_key, 'subjects')

      groups_file = Rails.root.join(subjects_dir, 'groups.csv')

      project = project_for_key project_key

      project.groups.destroy_all

      num_groups = File.foreach(groups_file).count - 1
      puts "Groups: Creating #{num_groups} groups from groups.csv"
      CSV.foreach(groups_file, :headers=>true, :header_converters=> lambda {|f| f.strip}, :converters=> lambda {|f| f ? f.strip : nil}) do |row|
        data = row.to_hash

        group_key        = data['key'].downcase
        name             = data['name']
        description      = data['description']
        cover_image_url  = data['cover_image_url']
        external_url     = data['external_url']
        meta_data        = data.except('name')

        group = project.groups.create({
                              name: name,
                              key: group_key,
                              description: description,
                              cover_image_url: cover_image_url,
                              external_url: external_url,
                              meta_data: meta_data})

        puts "  Creating group #{$. - 1} of #{num_groups}: #{group_key}"
        Rake::Task['load_group_subjects'].invoke(project_key, group_key)

        Rake::Task['load_group_subjects'].reenable

      end
    end

    task :load_group_subjects, [:project_key, :group_key] => :environment do |task, args|
      project_key = args[:project_key]
      subjects_dir = Rails.root.join('project', project_key, 'subjects')
      group_file = Rails.root.join subjects_dir, "group_#{args[:group_key]}.csv"

      group = Group.find_by key: args[:group_key]

      project = project_for_key args[:project_key]
      mark_workflow = project.workflows.find_by(name: 'mark')

      # Loop over contents of group file, which has one subject per row

      subjects_by_set = {}

      puts "    Reding subjects from: #{group_file}"
      CSV.foreach(group_file, :headers=>true, :header_converters=> lambda {|f| f.strip}, :converters=> lambda {|f| f ? f.strip : nil}) do |row|
        data = row.to_hash
        key = data['set_key']
        key = "_autogen_set_key_#{$.}" if key.blank?
        subjects_by_set[key] ||= []
        subjects_by_set[key] << data
      end

      subjects_by_set.each do |(set_key, subjects)|

        data = subjects.first
        thumbnail       = data['thumbnail']
        name            = data['name']
        meta_data       = data.except('group_id', 'file_path', 'retire_count', 'thumbnail', 'width','height', 'order')

        puts "    Adding subject set: #{set_key}"
        subject_set = group.subject_sets.create({
          name: name,
          project: project,
          thumbnail: thumbnail,
          meta_data: meta_data
        })
        puts "      - saved subject set #{subject_set.thumbnail}"

        subjects.each_with_index do |subj, i|
          data = subj

          width = subj['width'].nil? ? nil : subj['width'].to_i
          height = subj['height'].nil? ? nil : subj['height'].to_i

          # If width/height not specified in CSV, autodetect:
          if width.nil? || height.nil?
            require 'fastimage'
            width, height = FastImage.size(subj['file_path'])
            puts "        - Autodetected image size: #{width} x #{height}"
          end

          # Parse order from csv if avail; otherwise default to position in csv:
          order = subj['order'].nil? ? i : subj['order'].to_i

          puts "      Adding subject: #{subj['file_path']}"
          s = subject_set.subjects.create({
            # file_path: subj['file_path'], #PB: Nah, goes in location:
            location: {
              standard: subj['file_path'],
              thumbnail: subj['thumbnail']
            },
            workflow: mark_workflow,
            # retire_count: subj['retire_count'], # PB Don't see why we'd set this via csv
            meta_data: meta_data,
            width: width,
            height: height,
            order: order
          })
          s.activate!
          puts "        - Saved subject: #{s.location[:standard]}"
        end

      end
    end

