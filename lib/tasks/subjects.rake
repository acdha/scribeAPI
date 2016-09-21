require 'csv'
require 'active_support'
require 'ocr_alto'


namespace :subjects do
  desc 'links a chain of rake tasks to setup a project, groups, and subjects'

  # Given a project key (aka name/title), returns the Project instance from the db:
  def project_for_key(key)

    # project_file_path = Rails.root.join('project', key, 'project.json')
    # project_hash = JSON.parse File.read(project_file_path)

    project = Project.find_by key: key
    project
  end

  task :load_groups, [:project_key] => :environment do |task, args|
    project_key = args[:project_key]
    subjects_dir = Rails.root.join('project', project_key, 'subjects')

    groups_file = Rails.root.join(subjects_dir, 'groups.csv')

    project = project_for_key project_key

    # project.groups.destroy_all

    num_groups = File.foreach(groups_file).count - 1
    puts "Groups: Creating #{num_groups} groups from groups.csv"
    CSV.foreach(groups_file, :headers=>true, :header_converters=> lambda {|f| f.strip}, :converters=> lambda {|f| f ? f.strip : nil}) do |row|
      data = row.to_hash

      group_key        = data['key'] # .downcase # is there a reason for downcasing?
      name             = data['name']
      description      = data['description']
      cover_image_url  = data['cover_image_url']
      external_url     = data['external_url']
      meta_data        = data.except('name')

      group = project.groups.find_or_create_by key: group_key
      group.update_attributes({
        name: name,
        description: description,
        cover_image_url: cover_image_url,
        external_url: external_url,
        meta_data: meta_data
      })

      puts "  Creating group #{$. - 1} of #{num_groups}: #{group_key}"
      Rake::Task['subjects:load_group_subjects'].invoke(project_key, group_key)

      Rake::Task['subjects:load_group_subjects'].reenable

    end
  end

  task :load_group_subjects, [:project_key, :group_key] => :environment do |task, args|
    project_key = args[:project_key]
    subjects_dir = Rails.root.join('project', project_key, 'subjects')
    group_file = Rails.root.join subjects_dir, "group_#{args[:group_key]}.csv"

    project = project_for_key args[:project_key]
    group = project.groups.find_by key: args[:group_key]

    mark_workflow = project.workflows.find_by(name: 'mark')

    # Loop over contents of group file, which has one subject per row

    subjects_by_set = {}

    puts "    Reading subjects from: #{group_file}"
    if ! File.exist? group_file
      puts "Couldn't find #{group_file}"
    else
      CSV.foreach(group_file, :headers=>true, :header_converters=> lambda {|f| f.strip}, :converters=> lambda {|f| f ? f.strip : nil}) do |row|
        data = row.to_hash
        key = data['set_key']
        key = "_autogen_set_key_#{$.}" if key.blank?
        subjects_by_set[key] ||= []
        subjects_by_set[key] << data
      end
    end

    subjects_by_set.each do |(set_key, subjects)|

      data = subjects.first
      thumbnail       = data['thumbnail']
      name            = data['name']
      meta_data       = data.except('group_id', 'file_path', 'retire_count', 'thumbnail', 'width','height', 'order')

      puts "    Adding subject set: #{set_key}"
      subject_set = group.subject_sets.find_or_create_by key: set_key
      subject_set.update_attributes({
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
          width, height = FastImage.size(subj['file_path'],:raise_on_failure=>false, :timeout=>10.0)
          puts "        - Autodetected image size: #{width} x #{height}"
        end

        # Parse order from csv if avail; otherwise default to position in csv:
        order = subj['order'].nil? ? i : subj['order'].to_i

        # add zooniverse_id if exists
        if subj.has_key?("zooniverse_id")
          meta_data["zooniverse_id"] = subj["zooniverse_id"]
        end

        # puts "      Adding subject: #{subj['file_path']}"
        # Subject.all.where("location.standard" => "https://s3.amazonaws.com/scribe.nypl.org/emigrant-records/originals/037.jpg").count
        # puts "s = SubjectSet[#{subject_set.id}].subjects.where(\"location.standard\" => \"#{subj['file_path']}\").first"
        # puts "  updating metadata: #{meta_data}"

        subject = subject_set.subjects.where("location.standard" => subj['file_path'], type: 'root').first
        subject = subject_set.subjects.create if subject.nil?
        subject.update_attributes({
          location: {
            standard: subj['file_path'],
            thumbnail: subj['thumbnail']
          },
          workflow: mark_workflow,
          meta_data: meta_data,
          width: width,
          height: height,
          order: order,
          group: group
        })
        subject.activate!
        puts "Added subject: #{subject.location[:standard]}"

        # pre-create secondary mark subjects
        if !subj['alto'].nil?
          alto_url = subj['alto']
          puts "Parsing ALTO from #{alto_url} and create initial marks"
          headlines_info = OcrAlto::detect_headlines_from_alto(alto_url, max_num_headlines:16)
          page_width = headlines_info[:page_width]
          page_height = headlines_info[:page_height]
          headlines = headlines_info[:headlines]

          headlines.each do |headline|
            # create classification
            tb_width = (headline[:right] - headline[:left]) / page_width * width
            tb_height = (headline[:bottom] - headline[:top]) / page_height * height
            tb_hpos = headline[:left] / page_width * width
            tb_hpos = 0 if tb_hpos < 0
            tb_vpos = headline[:top] / page_height * height
            tb_vpos = 0 if tb_vpos < 0
            annotation = {
              "belongsToUser" => "true",
              "toolName" => "rectangleTool",
              "userCreated" => "false",
              "subToolIndex" => "0", # hardcoded one, assuming it is the first subtool
              "color" => "red",
              "isTranscribable" => "true",
              "x" => tb_hpos.to_s,
              "y" => tb_vpos.to_s,
              "width" => tb_width.to_s,
              "height" => tb_height.to_s,
              "_key" => Random.rand.to_s,
              "status" => "mark",
              "isUncommitted" => "true"
            }

            Classification.create(
              workflow: mark_workflow,
              subject: subject,
              location: nil,
              annotation: annotation,
              started_at: Time.now,
              finished_at: Time.now,
              user_agent: "Server",
              task_key: "mark_headline",  # TODO remove hardcoded task_key
              user: User.new() # User.id is required during subject creation
            )
          end
        end
      end
    end
  end
end
