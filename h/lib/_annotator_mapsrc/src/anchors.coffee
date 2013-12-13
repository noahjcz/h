# Abstract anchor class.
class Anchor

  constructor: (@annotator, @annotation, @target
      @startPage, @endPage,
      @quote, @diffHTML, @diffCaseOnly) ->

    unless @annotator? then throw "annotator is required!"
    unless @annotation? then throw "annotation is required!"
    unless @target? then throw "target is required!"
    unless @startPage? then "startPage is required!"
    unless @endPage? then throw "endPage is required!"
    unless @quote? then throw "quote is required!"

    @highlight = {}

    # Write our data back to the target
    @target.quote = @quote
    @target.diffHTML = @diffHTML
    @target.diffCaseOnly = @diffCaseOnly

    # Store this anchor for the annotation
    @annotation.anchors.push this

    # Update the annotation's anchor status

    # This annotation is no longer an orphan
    Util.removeFromSet @annotation, @annotator.orphans

    # Does it have all the wanted anchors?
    if @annotation.anchors.length is @annotation.target.length
      # Great. Not a half-orphan either.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now fully anchored."
      Util.removeFromSet @annotation, @annotator.halfOrphans
    else
      # No, some anchors are still missing. A half-orphan, then.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now a half-orphan."
      Util.addToSet @annotation, @annotator.halfOrphans

    # Store the anchor for all involved pages
    for pageIndex in [@startPage .. @endPage]
      @annotator.anchors[pageIndex] ?= []
      @annotator.anchors[pageIndex].push this

  # Return highlights for the given page
  _createHighlight: (page) ->
    throw "Function not implemented"

  # Create the missing highlights for this anchor
  realize: () =>
    return if @fullyRealized # If we have everything, go home

    # Collect the pages that are already rendered
    renderedPages = [@startPage .. @endPage].filter (index) =>
      @annotator.domMapper.isPageMapped index

    # Collect the pages that are already rendered, but not yet anchored
    pagesTodo = renderedPages.filter (index) => not @highlight[index]?

    return unless pagesTodo.length # Return if nothing to do

    try
      # Create the new highlights
      created = for page in pagesTodo
        @highlight[page] = @_createHighlight page

      # Check if everything is rendered now
      @fullyRealized = renderedPages.length is @endPage - @startPage + 1

      # Announce the creation of the highlights
      @annotator.publish 'highlightsCreated', created
    catch error
      console.log "Error while trying to create highlight:", error.stack

      @fullyRealized = false

      # Try to undo the highlights already created
      for page in pagesTodo when @highlight[page]
        try
          @highlight[page].removeFromDocument()
          console.log "Removed broken HL from page", page
        catch hlError
          console.log "Could not remove broken HL from page", page, ":", hlError.stack

  # Remove the highlights for the given set of pages
  virtualize: (pageIndex) =>
    highlight = @highlight[pageIndex]

    return unless highlight? # No highlight for this page

    try
      highlight.removeFromDocument()
    catch error
      console.log "Could not remove HL from page", pageIndex, ":", error.stack

    delete @highlight[pageIndex]

    # Mark this anchor as not fully rendered
    @fullyRealized = false

    # Announce the removal of the highlight
    @annotator.publish 'highlightRemoved', highlight

  # Virtualize and remove an anchor from all involved pages and the annotation
  remove: () ->
    # Go over all the pages
    for index in [@startPage .. @endPage]
      @virtualize index
      anchors = @annotator.anchors[index]
      # Remove the anchor from the list
      Util.removeFromSet this, anchors
      # Kill the list if it's empty
      delete @annotator.anchors[index] unless anchors.length

    # Remove the anchor from the list
    Util.removeFromSet this, @annotation.anchors

    # Are there any anchors remaining?
    if @annotation.anchors.length
      # This annotation is a half-orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is a half-orphan now."
      Util.addToSet @annotation, @annotator.halfOrphans
    else
      # This annotation is an orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is an orphan now."
      Util.addToSet @annotation, @annotator.orphans
      Util.removeFromSet @annotation, @annotator.halfOrphans

  # Check if this anchor is still valid. If not, remove it.
  verify: (reason, data) ->
    valid = if @strategy.verify # Do we have a way to verify this anchor?
      @strategy.verify this, reason, data
    else
      console.log "Can't verify this", @constructor.name, "because the",
        "'" + @strategy.name + "'",
        "strategy responsible for creating this anchor did not specify a verify function."
      false

    @remove() unless valid

  # Check if this anchor is still valid. If not, remove it.
  # This is called when the underlying annotation has been updated
  annotationUpdated: ->
    # Notify the highlights
    for index in [@startPage .. @endPage]
      @highlight[index]?.annotationUpdated()
