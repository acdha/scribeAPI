Classification          = require 'models/classification.coffee'

coreTools               = require 'components/core-tools'
markTools               = require 'components/mark/tools'
transcribeTools         = require 'components/transcribe/tools'
verifyTools             = require 'components/verify/tools'

module.exports =

  # Convenience method for selecting currently active workflow based on active controller
  getActiveWorkflow: ->
    return null if ! @props.project

    k = (k for w,k in @props.project.workflows when w.name == @props.workflowName)
    return null if k?.length != 1
    @props.project.workflows[k[0]]


  getWorkflowByName: (name) ->
    k = (k for w,k in @props.project.workflows when w.name is name)
    return null if k?.length != 1
    @props.project.workflows[k[0]]

  # Start a new classification (optionally initialized with given annotation hash):
  beginClassification: (annotation = {}, callback) ->
    classifications = @state.classifications
    classification = new Classification()

    if annotation?
      classification.annotation[k] = v for k, v of annotation

    classifications.push classification

    @setState
      classifications: classifications
      classificationIndex: classifications.length-1
        , =>
          @forceUpdate()
          window.classifications = @state.classifications # make accessible to console
          callback() if callback?

  commitClassification: (classification) ->
    return unless classification?

    # Create visual interim mark just in case POST takes a while
    interim_mark = @addInterimMark classification

    # Commit classification to backend
    classification.commit (classification) =>
      # Did this generate a child_subject? Update local copy:
      if classification.child_subject
        @appendChildSubject classification.subject_id, classification.child_subject

        # Now that we have the real mark, hide the interim mark:
        @hideInterimMark(interim_mark) if interim_mark?

      if @state.badSubject
        @toggleBadSubject =>
          @advanceToNextSubject()

      if @state.illegibleSubject
        @toggleIllegibleSubject =>
          @advanceToNextSubject()

  # Called immediately before saving a classification, adds a fake mark in lieu
  # of the real generated mark:
  addInterimMark: (classification) ->
    # Uniquely identify local interim marks:
    @interim_mark_id ||= 0

    # Interim mark is the region (the mark classification's annotation hash) with extras:
    interim_mark = $.extend({
      show:           true                        # Default to show. We'll disable this when classification saved
      interim_id:     (@interim_mark_id += 1)     # Unique id
      subject_id :    classification.subject_id   # Keep subject_id so we know which subject to show it over
    }, classification.annotation)

    # Add interim mark to array in @state
    interimMarks = @state.interimMarks ? []
    interimMarks.push interim_mark
    @setState interimMarks: interimMarks

    interim_mark

  # Counterpart to addInterimMark, hides the given interim mark
  hideInterimMark: (interim_mark) ->
    interimMarks = @state.interimMarks
    for m, i in interimMarks
      # If this is the interim mark to hide, hide it:
      if m.interim_id == interim_mark.interim_id
        m.show = false
        @setState interimMarks: interimMarks
        # We found it, move on:
        break

  commitCurrentClassification: () ->
    classification = @getCurrentClassification()
    classification.subject_id = @getCurrentSubject()?.id
    classification.subject_set_id = @getCurrentSubjectSet().id if @getCurrentSubjectSet()?
    classification.workflow_id = @getActiveWorkflow().id

    # If user activated 'Bad Subject' button, override task:
    if @state.moreSubject
      classification.task_key = 'completion_assessment_task'
      classification.annotation['value'] = 'incomplete_subject'
    else if @state.badSubject
      classification.task_key = 'flag_bad_subject_task'
    else if @state.illegibleSubject
      classification.task_key = 'flag_illegible_subject_task'
    # Otherwise, classification is for active task:
    else
      classification.task_key = @state.taskKey
      if Object.keys(classification.annotation).length == 0
        if @getActiveWorkflow().name is "mark" and not @getActiveWorkflow()?.show_completion_assessment_task
          # user clicking "Done", which implies complete_subject for completion_assessment_task
          classification.task_key = 'completion_assessment_task'
          classification.annotation['value'] = 'complete_subject'

      return if Object.keys(classification.annotation).length == 0

    @commitClassification(classification)
    @beginClassification()


  toggleBadSubject: (e, callback) ->
    @setState badSubject: not @state.badSubject, =>
      callback?()

  setMoreSubject: ->
    @state.moreSubject = true

  resetMoreSubject: ->
    @state.moreSubject = false

  toggleIllegibleSubject: (e, callback) ->
    @setState illegibleSubject: not @state.illegibleSubject, =>
      callback?()

  flagSubjectAsUserDeleted: (subject_id) ->
    classification = @getCurrentClassification()
    classification.subject_id = subject_id # @getCurrentSubject()?.id
    classification.workflow_id = @getActiveWorkflow().id
    classification.task_key = 'flag_bad_subject_task'

    classification.commit (classification) =>
      @updateChildSubject @getCurrentSubject().id, classification.subject_id, user_has_deleted: true
      @beginClassification()

  # Update specified child_subject with given properties (e.g. after submitting a delete flag)
  updateChildSubject: (parent_subject_id, child_subject_id, props) ->
    if (s = @getSubjectById(parent_subject_id))
      for c, i in s.child_subjects
        if c.id == child_subject_id
          c[k] = v for k,v of props

  # Add newly acquired child_subject to child_subjects array of relevant subject (i.e. after submitting a subject-generating classification)
  appendChildSubject: (subject_id, child_subject) ->
    if (s = @getSubjectById(subject_id))
      s.child_subjects.push $.extend({userCreated: true}, child_subject)

      # We've updated an internal object in @state.subjectSets, but framework doesn't notice, so tell it to update:
      @forceUpdate()

  # Get a reference to the local copy of a subject by id regardless of whether viewing subject-sets or just subjects
  getSubjectById: (id) ->
    if @state.subjectSets?

      # If current subject set has no subjects, we're likely in between one subject set
      # and the next (for which we're currently fetching subjects), so return null:
      return null if ! @getCurrentSubjectSet().subjects?

      for s in @getCurrentSubjectSet().subjects
        return s if s.id == id
    else
      for s in @state.subjects
        return s if s.id == id

  # Get current classification:
  getCurrentClassification: ->
    @state.classifications[@state.classificationIndex]


  # Get current task:
  getCurrentTask: ->
    return null if ! @state.taskKey?
    console.warn "TaskKey invalid: #{@state.taskKey}. Should be: #{(k for k,v of @getTasks())}" if ! @getTasks()[@state.taskKey]?
    @getTasks()[@state.taskKey]



  getTasks: ->
    # Add completion_assessment_task to list of tasks dynamically:
    tasks = @getActiveWorkflow().tasks
    completion_assessment_task = @getCompletionAssessmentTask()
    # Merge keys recursively if it exists in config
    completion_assessment_task = $.extend true, tasks['completion_assessment_task'], completion_assessment_task if tasks['completion_assessment_task']?
    $.extend tasks, completion_assessment_task: completion_assessment_task

  # Get instance of current tool:
  getCurrentTool: ->
    toolKey = @getCurrentTask()?.tool
    tool = @toolByKey toolKey

  toolByKey: (toolKey) ->
    ( ( coreTools[toolKey] ? markTools[toolKey] ) ? transcribeTools[toolKey] ) ? verifyTools[toolKey]

  # Load next logical task
  advanceToNextTask: () ->
    nextTaskKey = @getNextTask()?.key
    if nextTaskKey is null
      return

    # Commit whatever current classification is:
    @commitCurrentClassification()
    # start a new one:
    # @beginClassification {} # this keps adding empty (uncommitted) classifications to @state.classifications --STI

    # After classification ready with empty annotation, proceed to next task:
    @advanceToTask nextTaskKey

  # Get next logical task
  getNextTask: ->
    task = @getTasks()[@state.taskKey]
    # PB: Moving from hash of options to an array of options

    if (options = (c for c in task.tool_config?.options when c.value is @getCurrentClassification()?.annotation?.value)) && options.length > 0 && (opt = options[0])? && opt.next_task?
      nextKey = opt.next_task
    else
      nextKey = @getTasks()[@state.taskKey].next_task

    @getTasks()[nextKey]

  # Advance to a named task:
  advanceToTask: (key) ->
    task = @getTasks()[ key ]

    tool = @toolByKey task?.tool
    if ! task?
      console.warn "WARN: Invalid task key: ", key

    else if ! tool?
      console.warn "WARN: Invalid tool specified in #{key}: #{task.tool}"

    else
      @setState
        taskKey: key


  # Get currently viewed subject set
  getCurrentSubjectSet: ->
    if @state.subjectSets?[@state.subject_set_index]
      @state.subjectSets?[@state.subject_set_index]
    # else @state.subjectSets #having a hard time accounting for one subject_set

  # Get currently viewed subject
  getCurrentSubject: ->
    # If we've viewing a subject-set (i.e. Mark) let's use that subject-set's subjects

    if @getCurrentSubjectSet()?
      subjects = @getCurrentSubjectSet().subjects

    # Otherwise, since we're not viewing subject-sets, we must have an array of indiv subjects:
    else
      subjects = @state.subjects

    # It's possible we have no subjects at all, in which case fail with null:
    return null unless subjects?
    subjects[@state.subject_index] # otherwise, return subject

  getCompletionAssessmentTask: ->
    generates_subject_type: null
    instruction: "Thanks for all your work! Is there anything left to #{@props.workflowName}?"
    key: "completion_assessment_task"
    next_task: null
    tool: "pickOne"
    help: {
      title: "Completion Assessment",
      body: "<p>Have all requested fields on this page been marked with a rectangle?</p><p>You do not have to mark every field on the page, however, it helps us to know if you think there is more to mark. Thank you!</p>"
    },
    tool_config: {
      "options": [
        {
          "label": "Nothing left to #{@props.workflowName}",
          "next_task": null,
          "value": "complete_subject"
        },
        {
          "label": "There's more to #{@props.workflowName}",
          "next_task": null,
          "value": "incomplete_subject"
        }
      ]
    }
    subToolIndex: 0

  # Regardless of what workflow we're in, call this to display next subject (if any avail)
  advanceToNextSubject: ->
    if @state.subjects?
      @_advanceToNextSubjectInSubjects()
    else
      @_advanceToNextSubjectInSubjectSets()

  # This is the version of advanceToNextSubject for workflows that consume subjects (transcribe,verify)
  _advanceToNextSubjectInSubjects: ->
    if @state.subject_index + 1 < @state.subjects.length
      next_index = @state.subject_index + 1
      next_subject = @state.subjects[next_index]
      @setState
        taskKey: next_subject.type
        subject_index: next_index, =>
          key = @getCurrentSubject().type
          @advanceToTask key

    # Haz more pages of subjects?
    else if @state.subjects_next_page?
      @fetchSubjects page: @state.subjects_next_page

    else
      @setState
        subject_index: null
        noMoreSubjects: true
        userClassifiedAll: @state.subjects.length > 0

  # This is the version of advanceToNextSubject for workflows that consume subject sets (mark)
  _advanceToNextSubjectInSubjectSets: ->
    new_subject_set_index = @state.subject_set_index
    new_subject_index = @state.subject_index + 1

    # If we've exhausted pages in this subject set, move to next one:
    if new_subject_index >= @getCurrentSubjectSet().subjects.length
      new_subject_set_index += 1
      new_subject_index = 0

    # If we've exhausted all subject sets, collapse in shame
    if new_subject_set_index >= @state.subjectSets.length
      if @state.subject_sets_current_page < @state.subject_sets_total_pages
        # Gather filters by which to query subject-sets
        params =
          group_id:         @props.query.group_id ? null
          page:             @state.subject_sets_current_page + 1          
        @fetchSubjectSets params
      else
        @setState
          taskKey: null
          notice:
            header: "All Done!"
            message: "There's nothing more for you to #{@props.workflowName} here."
            onClick: () =>
              @transitionTo? 'mark' # "/#/mark"
              @setState
                notice: null
                taskKey: @getActiveWorkflow().first_task
        console.warn "NO MORE SUBJECT SETS"
      return

    # console.log "Mark#index Advancing to subject_set_index #{new_subject_set_index} (of #{@state.subjectSets.length}), subject_index #{new_subject_index} (of #{@state.subjectSets[new_subject_set_index].subjects.length})"

    @setState
      subject_set_index: new_subject_set_index
      subject_index: new_subject_index
      taskKey: @getActiveWorkflow().first_task
      currentSubToolIndex: 0, () =>
        @fetchSubjectsForCurrentSubjectSet(1, 100)

  commitClassificationAndContinue: (d) ->
    @commitCurrentClassification()
    @beginClassification {}, () =>
      if @getCurrentTask()?.next_task?
        @advanceToTask @getCurrentTask().next_task

      else
        @advanceToNextSubject()

  # Clear annotation. Used by skip to next subject action
  clearCurrentAnnotation: ->
    currentClassification = @getCurrentClassification()
    currentClassification.annotation = {}


  # Handle user selecting a pick/drawing tool:
  handleDataFromTool: (d) ->
    # Kind of a hack: We receive annotation data from two places:
    #  1. tool selection widget in right-col
    #  2. the actual draggable marking tools
    # We want to remember the subToolIndex so that the right-col menu highlights
    # the correct tool after committing a mark. If incoming data has subToolIndex
    # but no mark location information, we know this callback was called by the
    # right-col. So only in that case, record currentSubToolIndex, which we use
    # to initialize marks going forward
    if d.subToolIndex? && ! d.x? && ! d.y?
      @setState currentSubToolIndex: d.subToolIndex
      @setState currentSubtool: d.tool if d.tool?
    else
      classifications = @state.classifications
      classifications[@state.classificationIndex].annotation[k] = v for k, v of d

      # PB: Saving STI's notes here in case we decide tools should fully
      #   replace annotation hash rather than selectively update by key as above:
      # not clear whether we should replace annotations, or append to it --STI
      # classifications[@state.classificationIndex].annotation = d #[k] = v for k, v of d

      @setState
        classifications: classifications
          , =>
            @forceUpdate()

  cleanAnnotation: (annotation) ->
    # remove extra white spaces in strings as they are not important 
    # and only cause confusion during verifying
    for k,v of annotation
      if typeof v is 'string'
        v = v.trim()
        # replace multiple spaces and tabs with single space
        v = v.replace(/[ \t]+/g, " ")
        # replace multiple new lines with a single new line
        v = v.replace(/\n+/g, "\n")
        # remove spaces around new line
        v = v.replace(/ ?\n ?/g, "\n")
        annotation[k] = v


  handleTaskComplete: (d) ->
    @handleDataFromTool(d)
    # clean the classification's annotation before submit
    @cleanAnnotation @getCurrentClassification().annotation
    @commitClassificationAndContinue d


