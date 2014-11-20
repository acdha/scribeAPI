# @cjsx React.DOM
React = require 'react'
Draggable = require '../lib/draggable'
ResizeButton = require './resize-button'

RegionFocusTool = React.createClass
  displayName: 'RegionFocusTool'

  statics:
    defaultValues: ->
      @initStart arguments...

    initStart: ->
      @initMove arguments...

    initMove: ({x, y}) ->
      {x, y}

  getInitialState: ->
    console.log 'MARK PRO{P: ', @props.mark
    # # DEBUG CODE
    # console.log "PROPS [#{@props.mark.yUpper},#{@props.mark.yLower}]"
    # console.log "INITIAL (STATE.X, STATE.Y): (#{Math.round @props.mark.x},#{Math.round @props.mark.y})"
    centerX: @props.mark.x
    centerY: @props.mark.y
    markHeight: @props.defaultMarkHeight
    fillColor: 'rgba(0,0,0,0.5)'
    strokeColor: 'rgba(0,0,0,0.5)'
    strokeWidth: 6
    yUpper: @props.mark.yUpper
    yLower: @props.mark.yLower
    markHeight: @props.mark.yLower - @props.mark.yUpper

    markComplete: false
    transcribeComplete: false

  componentWillReceiveProps: ->
    @setState
      yUpper: @props.mark.yUpper
      yLower: @props.mark.yLower
      centerX: @props.mark.x
      centerY: @props.mark.y
      markHeight: @props.mark.yLower - @props.mark.yUpper, =>
        @forceUpdate()

  handleToolProgress: ->
    if @state.markComplete is false
      console.log 'MARK COMPLETE!'
      @setState markComplete: true
    else
      console.log 'TRANSCRIBE COMPLETE!'
      @setState transcribeComplete: true

  render: ->
    <g 
      className = "point drawing-tool" 
      transform = {"translate(#{Math.ceil @state.strokeWidth}, #{Math.round( @state.centerY - @state.markHeight/2 ) })"} 
      data-disabled = {@props.disabled || null} 
      data-selected = {@props.selected || null}
    >

      <Draggable
        onStart = {@props.handleMarkClick.bind @props.mark} 
        onDrag = {@props.handleDragMark} >
        <g>
          <rect 
            className   = "mark-rectangle"
            x           = 0
            y           = { -@state.yUpper }
            viewBox     = {"0 0 @props.imageWidth @props.imageHeight"}
            width       = {( @props.imageWidth - 2*@state.strokeWidth ) }
            height      = {@state.yUpper}
            fill        = "rgba(0,0,0,0.80)"
            stroke      = {@state.strokeColor}
            strokeWidth = {@state.strokeWidth}
          />
          <rect 
            className   = "mark-rectangle"
            x           = 0
            y           = { @state.markHeight }
            viewBox     = {"0 0 @props.imageWidth @props.imageHeight"}
            width       = {( @props.imageWidth - 2*@state.strokeWidth ) }
            height      = { @props.imageHeight - @state.yLower }
            fill        = "rgba(0,0,0,0.90)"
            stroke      = {@state.strokeColor}
            strokeWidth = {@state.strokeWidth}
          />
        </g>
      </Draggable>

      <ResizeButton 
        viewBox     = {"0 0 @props.imageWidth @props.imageHeight"}
        className = "upperResize"
        handleResize = {@props.handleUpperResize} 
        transform = {"translate( #{@props.imageWidth/2}, #{ - Math.round @props.scrubberHeight/2 } )"} 
        scrubberHeight = {@props.scrubberHeight}
        scrubberWidth = {@props.scrubberWidth}
        workflow = {@props.workflow}
        isSelected = "true"
      />

      <ResizeButton 
        className = "lowerResize"
        handleResize = {@props.handleLowerResize} 
        transform = {"translate( #{@props.imageWidth/2}, #{ Math.round( @state.markHeight - @props.scrubberHeight/2 ) } )"} 
        scrubberHeight = {@props.scrubberHeight}
        scrubberWidth = {@props.scrubberWidth}
        workflow = {@props.workflow}
        isSelected = "true"

      />

    </g>

module.exports = RegionFocusTool
  