# Annotator plugin providing dom-text-mapper
class Annotator.Plugin.DomTextMapper extends Annotator.Plugin

  pluginInit: ->
    # This plugin is intended to be used with the Enhanced Anchoring architecture.
    unless @annotator.plugins.EnhancedAnchoring
      throw new Error "The TextHighlights Annotator plugin requires the EnhancedAnchoring plugin."

    @Annotator = Annotator

    @annotator.anchoring.documentAccessStrategies.unshift
      # Document access strategy for simple HTML documents,
      # with enhanced text extraction and mapping features.
      name: "DOM-Text-Mapper"
      applicable: -> true
      get: =>
        defaultOptions =
          rootNode: @annotator.wrapper[0]
          getIgnoredParts: -> $.makeArray $ [
            "div.annotator-notice",
            "div.annotator-outer",
            "div.annotator-editor",
            "div.annotator-viewer",
            "div.annotator-adder"
          ].join ", "
          cacheIgnoredParts: true
        options = $.extend {}, defaultOptions, @options.options
        mapper = new window.DomTextMapper options
        options.rootNode.addEventListener "corpusChange", =>
          t0 = mapper.timestamp()
          @annotator.anchoring._reanchorAllAnnotations("corpus change").then ->
            t1 = mapper.timestamp()
            console.log "corpus change -> refreshed text annotations.",
              "Time used: ", t1-t0, "ms"
        mapper.scan "we are initializing d-t-m"
        mapper

