class @Gush
  constructor: ->
    @workflows = {}
    @machines = {}

  initialize: ->
    @registerSockets()
    @displayCurrentWorkflows()
    @displayJobsOverview()

  registerSockets: ->
    @registerWorkersSocket()
    @registerWorkflowsSocket()
    @registerMachinesSocket()

  displayCurrentWorkflows: ->
    $("table.workflows tbody").empty()
    ($("table.workflows").data("workflows") || []).each (workflow) =>
      @_addWorkflow(workflow)

  displayJobsOverview: ->
    if nodes?
      nodes.each (node) ->
        job = new Job(node)
        $("table.nodes tbody").append(job.render())

  registerWorkersSocket: ->
    workersSocket = new WebSocket(@_socketUrl("subscribe/workers.status"))

    workersSocket.onopen    = @_onOpen
    workersSocket.onerror   = @_onError
    workersSocket.onmessage = @_onStatus
    workersSocket.onclose   = @_onClose

  registerWorkflowsSocket: ->
    workflowsSocket = new WebSocket(@_socketUrl("subscribe/workflows.status"))

    workflowsSocket.onopen    = @_onOpen
    workflowsSocket.onerror   = @_onError
    workflowsSocket.onmessage = @_onWorkflowStatusChange
    workflowsSocket.onclose   = @_onClose

  registerMachinesSocket: ->
    machinesSocket = new WebSocket(@_socketUrl("workers"))

    machinesSocket.onopen    = @_onOpen
    machinesSocket.onerror   = @_onError
    machinesSocket.onmessage = @_onMachineStatusMessage

    machinesSocket.onclose   = @_onClose

  registerLogsSocket: (workflow, job) ->
    logsSocket = new WebSocket(@_socketUrl("/logs/#{workflow}.#{job}"))

    logsSocket.onopen    = @_onOpen
    logsSocket.onerror   = @_onError
    logsSocket.onmessage = (message) ->
      logs = JSON.parse(message.data)
      logs.forEach (log) ->
        $("ul.logs").append("<li>#{log}</li>")

    logsSocket.onclose   = @_onClose

  startWorkflow: (workflow, el) ->
    $.ajax
      url: "/start/" + workflow,
      type: "POST",
      error: (response) ->
        console.log(response)

    if el
      el.removeClass("success")
        .addClass("alert")
        .data("action", "stop")
        .contents().filter ->
          this.nodeType == 3
        .replaceWith("Stop workflow")

  startJob: (workflow, job, el) ->
    $.ajax
      url: "/start/#{workflow}/#{job}",
      type: "POST",
      error: (response) ->
        console.log(response)
      success: () ->
        window.location.href = "/show/#{workflow}"

  stopWorkflow: (workflow, el) ->
    if el
      el.addClass("success")
        .removeClass("alert")
        .data("action", "start")
        .contents().filter ->
          this.nodeType == 3
        .replaceWith("Start workflow")

  createWorkflow: (workflow) ->
    $.ajax
      url: "/create/" + workflow,
      type: "POST",
      error: (response) ->
        console.log(response)
      success: (response) =>
        @_addWorkflow(response);

  destroyWorkflow: (workflow) ->
    $.ajax
      url: "/destroy/" + workflow,
      type: "POST",
      error: (response) ->
        console.log(response)
      success: (response) =>
        window.location.href = "/"

  _onOpen: ->
    $("#modalBox").foundation("reveal", "close");

  _onError: (error) ->
    $("#modalBox .data").html("<h2>Lost connection with server.</h2> <h3>Reconnecting…</h3>");
    $("#modalBox").foundation("reveal", "open");

  _onClose: ->
    console.log("Connection closed");

  _onStatus: (message) =>
    message = JSON.parse(message.data)
    switch message.status
      when "started"
        @_onJobStart(message)
      when "finished"
        @_onJobSuccess(message)
      when "heartbeat"
        @_onJobHeartbeat(message)
      when "failed"
        @_onJobFail(message)
      else
        console.error("Unkown job status:", message.status, "data: ", message)

  _onWorkflowStatusChange: (message) =>
    message = JSON.parse(message.data)
    workflow = @workflows[message.workflow_id]
    if workflow
      workflow.changeStatus(message.status)
      workflow.updateDates(message)
      $("table.workflows").find("##{message.workflow_id}").replaceWith(workflow.render())

  _onMachineStatusMessage: (message) =>
      message = JSON.parse(message.data)
      message.each (machine) =>
        machine = @machines[message.id] ||= new Machine(machine, $("table.machines tbody"))
        machine.markAsAlive()
        machine.render()

  _onJobStart: (message) =>
    @_updateGraphStatus(message.workflow_id)

  _onJobSuccess: (message) =>
    @_updateGraphStatus(message.workflow_id)

    workflow = @workflows[message.workflow_id]
    if workflow
      workflow.updateProgress()
      $("table.workflows").find("##{message.workflow_id}").replaceWith(workflow.render())

  _onJobHeartbeat: (message) =>

  _onJobFail: (message) =>
    @_updateGraphStatus(message.workflow_id)

    workflow = @workflows[message.workflow_id]
    if workflow
      workflow.markAsFailed()
      $("table.workflows").find("##{message.workflow_id}").replaceWith(workflow.render())

  _addWorkflow: (data) =>
    workflow = new Workflow(data)
    @workflows[data.id] = workflow

    $("table.workflows").append(workflow.render())

  _updateGraphStatus: (workflow_id) ->
    $.ajax
      url: "/show/#{workflow_id}.json",
      type: "GET",
      error: (response) ->
        console.log(response)
      success: (response) =>
        graph = new Graph("canvas-#{workflow_id}")
        response.nodes.each (node) ->
          klasses = switch
            when node.failed then "status-finished status-failed"
            when node.finished then "status-finished"
            when node.enqueued then "status-running"
          graph.markNode(node.name, klasses)

  _socketUrl: (path) ->
    "ws://#{window.location.host}/#{path}"
