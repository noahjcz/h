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

    @Util = Annotator.Util

    # Update the annotation's anchor status

    # This annotation is no longer an orphan
    @Util.removeFromSet @annotation, @annotator.anchoring.orphans

    # Does it have all the wanted anchors?
    if @annotation.anchors.length is @annotation.target.length
      # Great. Not a half-orphan either.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now fully anchored."
      @Util.removeFromSet @annotation, @annotator.anchoring.halfOrphans
    else
      # No, some anchors are still missing. A half-orphan, then.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now a half-orphan."
      @Util.addToSet @annotation, @annotator.anchoring.halfOrphans

    # Store the anchor for all involved pages
    for pageIndex in [@startPage .. @endPage]
      @annotator.anchoring.anchors[pageIndex] ?= []
      @annotator.anchoring.anchors[pageIndex].push this

  # Return highlights for the given page
  _createHighlight: (page) ->
    throw "Function not implemented"

  # Create the missing highlights for this anchor
  realize: () =>
    return if @fullyRealized # If we have everything, go home

    # Collect the pages that are already rendered
    renderedPages = [@startPage .. @endPage].filter (index) =>
      @annotator.anchoring.domMapper.isPageMapped index

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
          console.log "Could not remove broken HL from page", page, ":",
            hlError.stack

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
      anchors = @annotator.anchoring.anchors[index]
      # Remove the anchor from the list
      @Util.removeFromSet this, anchors
      # Kill the list if it's empty
      delete @annotator.anchoring.anchors[index] unless anchors.length

    # Remove the anchor from the list
    @Util.removeFromSet this, @annotation.anchors

    # Are there any anchors remaining?
    if @annotation.anchors.length
      # This annotation is a half-orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is a half-orphan now."
      @Util.addToSet @annotation, @annotator.anchoring.halfOrphans
    else
      # This annotation is an orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is an orphan now."
      @Util.addToSet @annotation, @annotator.anchoring.orphans
      @Util.removeFromSet @annotation, @annotator.anchoring.halfOrphans

  # Check if this anchor is still valid. If not, remove it.
  verify: (reason, data) ->
    # Create a Deferred object
    dfd = Annotator.$.Deferred()

    # Do we have a way to verify this anchor?
    if @strategy.verify # We have a verify function to call.
      try
        @strategy.verify(this, reason, data).then (valid) =>
          @remove() unless valid        # Remove the anchor
          dfd.resolve()                 # Mark this as resolved
      catch error
        # The verify method crashed. How lame.
        console.log "Error while executing", @constructor.name,
          "'s verify method:", error.stack
        @remove()         # Remove the anchor
        dfd.resolve()     # Mark this as resolved
    else # No verify method specified
      console.log "Can't verify this", @constructor.name, "because the",
        "'" + @strategy.name + "'",
        "strategy (which was responsible for creating this anchor)"
        "did not specify a verify function."
      @remove()         # Remove the anchor
      dfd.resolve()     # Mark this as resolved

    # Return the promise
    dfd.promise()

  # Check if this anchor is still valid. If not, remove it.
  # This is called when the underlying annotation has been updated
  annotationUpdated: ->
    # Notify the highlights
    for index in [@startPage .. @endPage]
      @highlight[index]?.annotationUpdated()


# Abstract highlight class
class Highlight

  constructor: (@anchor, @pageIndex) ->
    @annotator = @anchor.annotator
    @annotation = @anchor.annotation

  # Mark/unmark this hl as temporary (while creating an annotation)
  setTemporary: (value) ->
    throw "Operation not implemented."

  # Is this a temporary hl?
  isTemporary: ->
    throw "Operation not implemented."

  # Mark/unmark this hl as active
  #
  # Value specifies whether it should be active or not
  #
  # The 'batch' field specifies whether this call is only one of
  # many subsequent calls, which should be executed together.
  #
  # In this case, a "finalizeHighlights" event will be published
  # when all the flags have been set, and the changes should be
  # executed.
  setActive: (value, batch = false) ->
    throw "Operation not implemented."

  # React to changes in the underlying annotation
  annotationUpdated: ->
    #console.log "In HL", this, "annotation has been updated."

  # Remove all traces of this hl from the document
  removeFromDocument: ->
    throw "Operation not implemented."

  # Get the HTML elements making up the highlight
  # If you implement this, you get automatic implementation for the functions
  # below. However, if you need a more sophisticated control mechanism,
  # you are free to leave this unimplemented, and manually implement the
  # rest.
  _getDOMElements: ->
    throw "Operation not implemented."

  # Get the Y offset of the highlight. Override for more control
  getTop: -> $(@_getDOMElements()).offset().top

  # Get the height of the highlight. Override for more control
  getHeight: -> $(@_getDOMElements()).outerHeight true

  # Get the bottom Y offset of the highlight. Override for more control.
  getBottom: -> @getTop() + @getBottom()

  # Scroll the highlight into view. Override for more control
  scrollTo: -> $(@_getDOMElements()).scrollintoview()

  # Scroll the highlight into view, with a comfortable margin.
  # up should be true if we need to scroll up; false otherwise
  paddedScrollTo: (direction) ->
    unless direction? then throw "Direction is required"
    dir = if direction is "up" then -1 else +1
    where = $(@_getDOMElements())
    wrapper = @annotator.wrapper
    defaultView = wrapper[0].ownerDocument.defaultView
    pad = defaultView.innerHeight * .2
    where.scrollintoview
      complete: ->
        scrollable = if this.parentNode is this.ownerDocument
          $(this.ownerDocument.body)
        else
          $(this)
        top = scrollable.scrollTop()
        correction = pad * dir
        scrollable.stop().animate {scrollTop: top + correction}, 300

  # Scroll up to the highlight, with a comfortable margin.
  paddedScrollUpTo: -> @paddedScrollTo "up"

  # Scroll down to the highlight, with a comfortable margin.
  paddedScrollDownTo: -> @paddedScrollTo "down"


# Fake two-phase / pagination support, used for HTML documents
class DummyDocumentAccess

  constructor: (@rootNode) ->
  @applicable: -> true
  getPageIndex: -> 0
  getPageCount: -> 1
  getPageRoot: -> @rootNode
  getPageIndexForPos: -> 0
  isPageMapped: -> true

# Enhanced Anchoring Manager

class EnhancedAnchoringManager extends Annotator.AnchoringManager

  constructor: (@annotator) ->
    console.log "Initializing Enhanced Anchoring Manager"

    @anchoringStrategies = []

    @_setupDocumentAccessStrategies()
    @_setupAnchorEvents()

    # Create buckets for orphan and half-orphan annotations
    @orphans = []
    @halfOrphans = []

  # Initializes the available document access strategies
  _setupDocumentAccessStrategies: ->
    @documentAccessStrategies = [
      # Default dummy strategy for simple HTML documents.
      # The generic fallback.
      name: "Dummy"
      applicable: -> true
      get: => new DummyDocumentAccess @wrapper[0]
    ]

  # Sets up handlers to anchor-related events
  _setupAnchorEvents: ->
    # When annotations are updated
    @annotator.on 'annotationUpdated', (annotation) =>
      # Notify the anchors
      for anchor in annotation.anchors or []
        anchor.annotationUpdated()

  # Initializes the components used for analyzing the document
  _chooseAccessPolicy: ->
    # We only have to do this once.
    return if @domMapper

    # Go over the available strategies
    for s in @documentAccessStrategies
      # Can we use this strategy for this document?
      if s.applicable()
        @documentAccessStrategy = s
        console.log "Selected document access strategy: " + s.name
        @domMapper = s.get()
        @anchors = {}
        addEventListener "docPageMapped", (evt) =>
          @_realizePage evt.pageIndex
        addEventListener "docPageUnmapped", (evt) =>
          @_virtualizePage evt.pageIndex
        return this

  # Recursive method to go over the passed list of strategies,
  # and create an anchor with the first one that succeeds.
  _createAnchorWithStrategies: (annotation, target, strategies, promise) ->

    # Fetch the next strategy to try
    s = strategies.shift()

    # We will do this if this strategy failes
    onFail = (error) =>
#      console.log "Anchoring strategy",
#        "'" + s.name + "'",
#        "has failed:",
#        error

      # Do we have more strategies to try?
      if strategies.length
        # Check the next strategy.
        @_createAnchorWithStrategies annotation, target, strategies, promise
      else
        # No, it's game over
        promise.reject()

    try
      # Get a promise from this strategy
      iteration = s.create annotation, target

      # Run this strategy
      iteration.then( (anchor) => # This strategy has worked.
#        console.log "Anchoring strategy '" + s.name + "' has succeeded:",
#          anchor

        # Note the name of the successful strategy
        anchor.strategy = s

        # We can now resolve the promise
        promise.resolve anchor

      ).fail onFail
    catch error
      # The strategy has thrown an error!
      console.log "While trying anchoring strategy",
        "'" + s.name + "':",
      console.log error.stack
      onFail "see exception above"

    null

  # Try to find the right anchoring point for a given target
  #
  # Returns a promise, which will be resolved with an Anchor object
  _createAnchor: (annotation, target) ->
    unless target?
      throw new Error "Trying to find anchor for null target!"
    #console.log "Trying to find anchor for target: ", target

    # Create a Deferred object
    dfd = Annotator.$.Deferred()

    # Start to go over all the strategies
    @_createAnchorWithStrategies annotation, target,
      @anchoringStrategies.slice(), dfd

    # Return the promise
    dfd.promise()

  # Find the anchor belonging to a given target
  _findAnchorForTarget: (annotation, target) ->
    for anchor in annotation.anchors when anchor.target is target
      return anchor
    return null

  # Decides whether or not a given target is anchored
  _hasAnchorForTarget: (annotation, target) ->
    anchor = this._findAnchorForTarget annotation, target
    anchor?

  # Tries to create any missing anchors for the given annotation
  # Optionally accepts a filter to test targetswith
  _anchorAnnotation: (annotation, targetFilter, publishEvent = false) ->

    # Supply a dummy target filter, if needed
    targetFilter ?= (target) -> true

    # Build a filter to test targets with.
    shouldDo = (target) =>
      (not this._hasAnchorForTarget annotation, target) and # has no ancher
        (targetFilter target)  # Passes the optional filter

    annotation.quote = (t.quote for t in annotation.target)
    annotation.anchors ?= []

    # Collect promises for all the involved targets
    promises = for t in annotation.target when shouldDo t

      index = annotation.target.indexOf t

      # Create an anchor for this target
      this._createAnchor(annotation, t).then (anchor) =>
        # We have an anchor
        annotation.quote[index] = t.quote

        # Realizing the anchor
        anchor.realize()

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    Annotator.$.when(promises...).always =>

      # Join all the quotes into one string.
      annotation.quote = annotation.quote.filter((q)->q?).join ' / '

      # Did we actually manage to anchor anything?
      if "resolved" in (p.state() for p in promises)

        if this.changedAnnotations? # Are we collecting anchoring changes?
          this.changedAnnotations.push annotation  # Add this annotation

        if publishEvent  # Are we supposed to publish an event?
          this.publish "annotationsLoaded", [[annotation]]

      # We are done!
      dfd.resolve annotation

    # Return a promise
    dfd.promise()

  # Tries to create any missing anchors for all annotations
  _anchorAllAnnotations: (targetFilter) ->
    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    # We have to consider the orphans and half-orphans, since they are
    # the onees with missing annotations
    annotations = this.halfOrphans.concat this.orphans

    # Initiate the collection of changes
    this.changedAnnotations = []

    # Get promises for anchoring all annotations
    promises = for annotation in annotations
      this._anchorAnnotation annotation, targetFilter

    # Wait for all attempts for finish/fail
    Annotator.$.when(promises...).always =>

      # send out notifications and updates
      if this.changedAnnotations.length
        this.publish "annotationsLoaded", [this.changedAnnotations]
      delete this.changedAnnotations

      # When all is said and done
      dfd.resolve()

    # Return a promise
    dfd.promise()


  # Collect all the highlights (optionally for a given set of annotations)
  getHighlights: (annotations) ->
    results = []
    if annotations?
      # Collect only the given set of annotations
      for annotation in annotations
        for anchor in annotation.anchors
          for page, hl of anchor.highlight
            results.push hl
    else
      # Collect from everywhere
      for page, anchors of @anchors
        $.merge results, (anchor.highlight[page] for anchor in anchors when anchor.highlight[page]?)
    results

  # Realize anchors on a given pages
  _realizePage: (index) ->
    # If the page is not mapped, give up
    return unless @domMapper.isPageMapped index

    # Go over all anchors related to this page
    for anchor in @anchors[index] ? []
      anchor.realize()

  # Virtualize anchors on a given page
  _virtualizePage: (index) ->
    # Go over all anchors related to this page
    for anchor in @anchors[index] ? []
      anchor.virtualize index

  # Tell all anchors to verify themselves
  _verifyAllAnchors: (reason = "no reason in particular", data = null) =>
#    console.log "Verifying all anchors, because of", reason, data

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    promises = [] # Let's collect promises from all anchors

    for page, anchors of @anchors     # Go over all the pages
      for anchor in anchors.slice()   # and all the anchors
        promises.push anchor.verify reason, data    # and verify them

    # Wait for all attempts for finish/fail
    Annotator.$.when(promises...).always -> dfd.resolve()

    # Return a promise
    dfd.promise()

  # Re-anchor all the annotations
  _reanchorAllAnnotations: (reason = "no reason in particular",
      data = null, targetFilter = null
  ) =>

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    this._verifyAllAnchors(reason, data)     # Verify all anchors
    .then => this._anchorAllAnnotations(targetFilter) # re-create anchors
    .then -> dfd.resolve()   # we are done

    # Return a promise
    dfd.promise()

  # Set up the anchoring system
  init: ->
    # To work with annotations, we need to have a document access policy.        
    @_chooseAccessPolicy()

  onSetup: (annotation) ->

    # In the lonely world of annotations, everybody is born as an orphan.
    @orphans.push annotation

    # In order to change this, let's try to anchor this annotation!
    @_anchorAnnotation annotation

  onDelete: (annotation) ->

    if annotation.anchors?                     # If we have anchors,
      a.remove() for a in annotation.anchors   # remove them

    # By the time we delete them, every annotation is an orphan,
    # (since we have just deleted all of it's anchors),
    # so time to remove it from the orphan list.
    Annotator.Util.removeFromSet annotation, @orphans

  onSetTemporary: (annotation, value) ->
    hl.setTemporary value for hl in @getHighlights [annotation]        


class Annotator.Plugin.EnhancedAnchoring extends Annotator.Plugin

  pluginInit: ->
    @annotator.anchoring = new EnhancedAnchoringManager @annotator

Annotator.Highlight = Highlight
Annotator.Anchor = Anchor
