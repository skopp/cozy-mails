{MessageBoxElement} = require "./message_box_element"

###
  @file: message_box.coffee
  @author: Mikolaj Pawlikowski (mikolaj@pawlikowski.pl/seeker89@github)
  @description: 
    Serves a place to display messages which are meant to be seen by user.

###

class exports.MessageBox extends Backbone.View

  constructor: (@el, @collection) ->
    super()

  initialize: ->
    @collection.on "add", @addOne, @
    @collection.on "reset", @render, @

  # Add a mailbox at the bottom of the list
  addOne: (logmessage) ->
    box = new MessageBoxElement logmessage, @collection
    $(@el).append box.render().el    

  render: ->
    $(@el).html ""
    col = @collection
    @collection.each (m) =>
      @addOne m
    @
