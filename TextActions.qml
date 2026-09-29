import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Overlay that runs an AI action over the text the user selected in any
// window. The text is captured by bin/text-actions (the keybinding path) and
// handed in as `{"text": "..."}`; running, pasting and copying all go back
// through that script, which owns the provider config and the API key.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string selectedText: ""
  property string filterText: ""
  property var allActions: []
  property var filtered: []
  property int selectedIndex: 0
  property string mode: "actions" // actions | result
  property bool busy: false
  property string resultText: ""
  property string errorText: ""
  property bool stagedSelection: false

  // Settings: the model list lives in the one config file the script owns.
  property var config: ({ version: 2, defaultModel: "", models: [] })
  property var configModels: []
  property string defaultModelId: ""
  property int settingsIndex: 0
  property string editingId: ""
  property string settingsError: ""
  property string fLabel: ""
  property string fType: "openai"
  property string fBaseUrl: ""
  property string fModel: ""
  property string fApiKey: ""
  property string fApiKeyEnv: ""
  property string fKeyCommand: ""
  property string fEndpoint: ""
  property string fDeployment: ""
  property string fApiVersion: ""

  readonly property string pluginId: (root.manifest && root.manifest.id) || "nichovski.text-actions"
  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId + "/bin/text-actions"

  readonly property int maxText: 100000

  // Shares the [menu] surface tokens so themes style this like the menu.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedForeground: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.sm
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(42), Style.font.title + Style.spacing.controlPaddingY * 2)

  // --- lifecycle -------------------------------------------------------

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) { payload = {} }
    root.selectedText = String(payload.text || "")
    root.stagedSelection = payload.staged === true
    root.filterText = ""
    root.selectedIndex = 0
    root.mode = "actions"
    root.busy = false
    root.resultText = ""
    root.errorText = ""
    root.refilter()
    root.opened = true
    if (root.stagedSelection) { selectionProc.running = false; selectionProc.running = true }
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  // Read by `text-actions toggle` so the keybinding knows whether to close.
  function isOpen() { return root.opened ? "true" : "false" }

  // --- actions ---------------------------------------------------------

  function setActions(list) {
    root.allActions = Array.isArray(list) ? list : []
    root.refilter()
  }

  function refilter() {
    var q = root.filterText.trim().toLowerCase()
    if (!q) {
      root.filtered = root.allActions.slice()
    } else {
      root.filtered = root.allActions.filter(function(a) {
        return String(a.label).toLowerCase().indexOf(q) !== -1
      })
    }
    if (root.selectedIndex >= root.filtered.length)
      root.selectedIndex = Math.max(0, root.filtered.length - 1)
  }

  function move(delta) {
    if (root.filtered.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.filtered.length) % root.filtered.length
  }

  function submit() {
    if (root.busy) return
    if (root.filtered.length > 0) {
      root.runAction(root.filtered[Math.max(0, Math.min(root.selectedIndex, root.filtered.length - 1))].id)
    } else if (root.filterText.trim() !== "") {
      root.runCustom(root.filterText.trim())
    }
  }

  function runAction(id) {
    root.mode = "result"
    root.busy = true
    root.resultText = ""
    root.errorText = ""
    var args = [root.scriptPath, "run"]
    if (root.stagedSelection) args.push("--staged")
    args.push("--action"); args.push(id)
    if (!root.stagedSelection) { args.push("--"); args.push(root.selectedText) }
    runProc.command = args
    runProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function runCustom(instruction) {
    root.mode = "result"
    root.busy = true
    root.resultText = ""
    root.errorText = ""
    var args = [root.scriptPath, "run"]
    if (root.stagedSelection) args.push("--staged")
    args.push("--custom")
    if (!root.stagedSelection) { args.push("--"); args.push(root.selectedText) }
    runProc.instruction = instruction
    runProc.command = args
    runProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function backToActions() {
    if (root.busy) return
    root.mode = "actions"
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function replaceSelection() {
    if (root.busy || root.resultText === "") return
    root.dismiss()
    pasteProc.command = [root.scriptPath, "paste"]
    pasteProc.running = true
  }

  function copyResult() {
    if (root.busy || root.resultText === "") return
    copyProc.command = [root.scriptPath, "copy"]
    copyProc.running = true
    root.dismiss()
  }

  // --- settings --------------------------------------------------------

  function currentModelLabel() {
    for (var i = 0; i < root.configModels.length; i++) {
      if (root.configModels[i].id === root.defaultModelId)
        return String(root.configModels[i].label || root.configModels[i].id)
    }
    return root.configModels.length > 0 ? "no default" : "no models"
  }

  function reloadConfig() {
    configProc.running = false
    configProc.running = true
  }

  function applyConfig(jsonText) {
    var cfg = {}
    try { cfg = JSON.parse(String(jsonText || "{}")) } catch (e) { cfg = {} }
    root.config = cfg
    root.configModels = Array.isArray(cfg.models) ? cfg.models : []
    root.defaultModelId = String(cfg.defaultModel || "")
    if (root.settingsIndex >= root.configModels.length)
      root.settingsIndex = Math.max(0, root.configModels.length - 1)
    if (root.mode === "settings")
      Qt.callLater(function() { settingsView.forceActiveFocus() })
  }

  function openSettings() {
    root.settingsError = ""
    root.mode = "settings"
    root.reloadConfig()
  }

  function selectForEdit(m) {
    root.editingId = String(m.id || "")
    root.fLabel = String(m.label || "")
    root.fType = String(m.type || "openai")
    root.fBaseUrl = String(m.baseUrl || "")
    root.fModel = String(m.model || "")
    root.fApiKey = String(m.apiKey || "")
    root.fApiKeyEnv = String(m.apiKeyEnv || "")
    root.fKeyCommand = String(m.keyCommand || "")
    root.fEndpoint = String(m.endpoint || "")
    root.fDeployment = String(m.deployment || "")
    root.fApiVersion = String(m.apiVersion || "2024-10-21")
    root.settingsError = ""
    root.mode = "edit"
  }

  function newModel() {
    root.selectForEdit({ id: "", label: "", type: "openai" })
  }

  function saveModel() {
    root.settingsError = ""
    if (root.fModel.trim() === "") { root.settingsError = "The model field is required."; return }
    var m = {
      id: root.editingId,
      label: root.fLabel.trim() !== "" ? root.fLabel.trim() : root.fModel.trim(),
      type: root.fType,
      model: root.fModel.trim(),
      baseUrl: root.fBaseUrl.trim(),
      apiKey: root.fApiKey,
      apiKeyEnv: root.fApiKeyEnv.trim(),
      keyCommand: root.fKeyCommand.trim(),
      endpoint: root.fEndpoint.trim(),
      deployment: root.fDeployment.trim(),
      apiVersion: root.fApiVersion.trim()
    }
    saveProc.payload = JSON.stringify(m)
    saveProc.running = true
  }

  function deleteModel() {
    if (root.editingId === "") return
    deleteProc.command = [root.scriptPath, "model-delete", root.editingId]
    deleteProc.running = true
  }

  function useModel(id) {
    useProc.command = [root.scriptPath, "set-model", id]
    useProc.running = true
  }

  // --- processes -------------------------------------------------------

  Process {
    id: listProc
    command: [root.scriptPath, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.setActions(JSON.parse(text)) } catch (e) { root.setActions([]) }
      }
    }
  }

  Process {
    id: runProc
    property string instruction: ""
    stdinEnabled: true
    onStarted: {
      if (runProc.instruction !== "") {
        write(runProc.instruction + "\n")
        runProc.instruction = ""
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.resultText = text.slice(0, root.maxText)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.errorText = text.trim().slice(0, root.maxText)
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        if (root.errorText === "") root.errorText = "Request failed"
        root.resultText = ""
      }
    }
  }

  Process {
    id: selectionProc
    command: [root.scriptPath, "selection"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.selectedText = text.slice(0, root.maxText) }
  }

  Process { id: pasteProc }
  Process { id: copyProc }

  Process {
    id: configProc
    command: [root.scriptPath, "config"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyConfig(text.slice(0, 1000000)) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.settingsError = text.trim().slice(0, root.maxText) }
  }

  Process {
    id: saveProc
    property string payload: ""
    stdinEnabled: true
    command: [root.scriptPath, "model-save"]
    onStarted: {
      if (saveProc.payload !== "") {
        write(saveProc.payload + "\n")
        saveProc.payload = ""
      }
    }
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.settingsError = text.trim().slice(0, root.maxText) }
    onExited: function(code) {
      if (code === 0) { root.mode = "settings"; root.reloadConfig() }
      else if (root.settingsError === "") root.settingsError = "Could not save the model."
    }
  }

  Process {
    id: deleteProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.settingsError = text.trim().slice(0, root.maxText) }
    onExited: function(code) {
      if (code === 0) { root.mode = "settings"; root.reloadConfig() }
      else if (root.settingsError === "") root.settingsError = "Could not delete the model."
    }
  }

  Process {
    id: useProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.settingsError = text.trim().slice(0, root.maxText) }
    onExited: function(code) {
      if (code === 0) root.reloadConfig()
      else if (root.settingsError === "") root.settingsError = "Could not set the default model."
    }
  }

  Component.onCompleted: {
    listProc.running = true
    configProc.running = true
  }

  // --- UI --------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-text-actions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Result mode has no text field to hold focus, so this catches the keys.
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.mode === "result"
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.backToActions()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.replaceSelection()
            event.accepted = true
          }
        }
      }

      // --- Settings: manage models ------------------------------------
      ColumnLayout {
        id: settingsView
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.mode === "settings"
        focus: root.mode === "settings"
        spacing: root.contentSpacing
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.mode = "actions"
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.configModels.length > 0) root.settingsIndex = Math.min(root.settingsIndex + 1, root.configModels.length - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.configModels.length > 0) root.settingsIndex = Math.max(root.settingsIndex - 1, 0)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.settingsIndex < root.configModels.length) root.selectForEdit(root.configModels[root.settingsIndex])
            event.accepted = true
          } else if (event.text === "n") {
            root.newModel()
            event.accepted = true
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: root.contentSpacing
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Models"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
          Button {
            text: "+ Add"
            foreground: root.foreground
            accent: Color.accent
            onClicked: root.newModel()
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.settingsError !== ""
          textFormat: Text.PlainText
          text: root.settingsError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          visible: root.configModels.length === 0
          textFormat: Text.PlainText
          text: "No models yet. Press “+ Add” to configure one."
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        ListView {
          id: modelList
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.configModels.length > 0
          clip: true
          model: root.configModels
          boundsBehavior: Flickable.StopAtBounds
          spacing: Style.space(2)

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool hot: index === root.settingsIndex
            readonly property bool isDefault: root.defaultModelId === modelData.id

            width: modelList.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: hot ? root.selectedBackground : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              spacing: Style.spacing.controlPaddingX

              Text {
                textFormat: Text.PlainText
                text: isDefault ? "●" : "○"
                color: hot ? root.selectedForeground : root.foreground
                font.pixelSize: Style.font.body
                Layout.preferredWidth: Style.space(18)
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  textFormat: Text.PlainText
                  text: modelData.label || modelData.id
                  color: hot ? root.selectedForeground : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
                Text {
                  textFormat: Text.PlainText
                  text: (modelData.type === "azure" ? "Azure · " : "") + (modelData.model || "")
                  color: hot ? root.selectedForeground : root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }

              Button {
                visible: !isDefault
                text: "Use"
                foreground: hot ? root.selectedForeground : root.foreground
                onClicked: root.useModel(modelData.id)
              }
            }

            MouseArea {
              anchors.fill: parent
              anchors.rightMargin: Style.space(72)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.settingsIndex = index
              onClicked: root.selectForEdit(modelData)
            }
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Enter edit  ·  n new  ·  Esc close"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // --- Edit one model ---------------------------------------------
      Flickable {
        id: editView
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.mode === "edit"
        focus: root.mode === "edit"
        clip: true
        contentWidth: width
        contentHeight: editCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.settingsError = ""
            root.mode = "settings"
            event.accepted = true
          } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.saveModel()
            event.accepted = true
          }
        }

        ColumnLayout {
          id: editCol
          width: editView.width
          spacing: root.contentSpacing

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.editingId === "" ? "New model" : "Edit model"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            Layout.fillWidth: true
            visible: root.settingsError !== ""
            textFormat: Text.PlainText
            text: root.settingsError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "Name (e.g. Claude Sonnet)"
            text: root.fLabel
            foreground: root.foreground
            onTextEdited: root.fLabel = text
          }

          Dropdown {
            Layout.fillWidth: true
            label: "API type"
            value: root.fType
            options: [
              { value: "openai", label: "OpenAI-compatible" },
              { value: "azure", label: "Azure OpenAI" }
            ]
            foreground: root.foreground
            onChanged: root.fType = value
          }

          TextField {
            Layout.fillWidth: true
            visible: root.fType !== "azure"
            placeholderText: "Base URL (e.g. https://openrouter.ai/api/v1)"
            text: root.fBaseUrl
            foreground: root.foreground
            onTextEdited: root.fBaseUrl = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "Model (e.g. openai/gpt-4o-mini)"
            text: root.fModel
            foreground: root.foreground
            onTextEdited: root.fModel = text
          }

          TextField {
            Layout.fillWidth: true
            visible: root.fType === "azure"
            placeholderText: "Endpoint (https://<resource>.openai.azure.com)"
            text: root.fEndpoint
            foreground: root.foreground
            onTextEdited: root.fEndpoint = text
          }

          TextField {
            Layout.fillWidth: true
            visible: root.fType === "azure"
            placeholderText: "Deployment name"
            text: root.fDeployment
            foreground: root.foreground
            onTextEdited: root.fDeployment = text
          }

          TextField {
            Layout.fillWidth: true
            visible: root.fType === "azure"
            placeholderText: "API version"
            text: root.fApiVersion
            foreground: root.foreground
            onTextEdited: root.fApiVersion = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "API key (stored in the config file)"
            password: true
            text: root.fApiKey
            foreground: root.foreground
            onTextEdited: root.fApiKey = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "API key env var (optional)"
            text: root.fApiKeyEnv
            foreground: root.foreground
            onTextEdited: root.fApiKeyEnv = text
          }

          TextField {
            Layout.fillWidth: true
            placeholderText: "Key command (optional, e.g. pass show openai)"
            text: root.fKeyCommand
            foreground: root.foreground
            onTextEdited: root.fKeyCommand = text
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Key order: API key, then env var, then command."
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: root.contentSpacing
            Button {
              text: "Save"
              selected: true
              foreground: root.foreground
              accent: Color.accent
              onClicked: root.saveModel()
            }
            Button {
              visible: root.editingId !== "" && root.defaultModelId !== root.editingId
              text: "Set as default"
              foreground: root.foreground
              onClicked: root.useModel(root.editingId)
            }
            Item { Layout.fillWidth: true }
            Button {
              visible: root.editingId !== ""
              text: "Delete"
              foreground: Color.urgent
              onClicked: root.deleteModel()
            }
            Button {
              text: "Back"
              foreground: root.foreground
              onClicked: { root.settingsError = ""; root.mode = "settings" }
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Ctrl+S save  ·  Esc back"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.mode === "actions" || root.mode === "result"
        spacing: root.contentSpacing

        TextField {
          id: input
          Layout.fillWidth: true
          visible: root.mode === "actions"
          placeholderText: "What to do with the selected text?"
          font.family: root.fontFamily
          foreground: root.foreground
          onTextChanged: {
            root.filterText = text
            root.selectedIndex = 0
            root.refilter()
          }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) {
              root.openSettings()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.move(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.move(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.submit()
              event.accepted = true
            }
          }
        }

        // Preview of what will be edited.
        Text {
          Layout.fillWidth: true
          Layout.maximumHeight: Style.space(44)
          visible: root.mode === "actions"
          textFormat: Text.PlainText
          text: root.selectedText !== "" ? root.selectedText : "No text selected - type an instruction and press Enter."
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: root.mode === "actions" && root.filtered.length > 0
          text: "Actions for selected text"
          color: root.foreground
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
        }

        ListView {
          id: actionList
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.mode === "actions"
          clip: true
          model: root.filtered
          boundsBehavior: Flickable.StopAtBounds
          spacing: Style.space(2)

          delegate: Rectangle {
            required property var modelData
            required property int index

            readonly property bool hot: index === root.selectedIndex

            width: actionList.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: hot ? root.selectedBackground : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              spacing: Style.spacing.controlPaddingX

              Text {
                textFormat: Text.PlainText
                text: modelData.icon || ""
                color: hot ? root.selectedForeground : root.foreground
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                Layout.preferredWidth: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.label || ""
                color: hot ? root.selectedForeground : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
              onClicked: {
                root.selectedIndex = index
                root.runAction(modelData.id)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width
            visible: root.filtered.length === 0 && root.filterText.trim() !== ""
            textFormat: Text.PlainText
            text: "Press Enter to apply “" + root.filterText.trim() + "”"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }

        // Result pane.
        Flickable {
          id: resultPane
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.mode === "result"
          clip: true
          contentWidth: width
          contentHeight: resultBody.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: resultBody
            width: resultPane.width
            textFormat: Text.PlainText
            text: root.busy ? "Working…"
              : (root.errorText !== "" ? root.errorText : root.resultText)
            color: root.errorText !== "" ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // Footer.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlPaddingX

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.mode === "result"
              ? (root.busy ? "" : "Enter to replace  ·  Esc to go back")
              : "Enter to submit  ·  Esc to close"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            visible: root.mode === "actions"
            text: "Model: " + root.currentModelLabel()
            foreground: root.foreground
            onClicked: root.openSettings()
          }

          Button {
            visible: root.mode === "result" && !root.busy && root.resultText !== ""
            text: "Copy"
            foreground: root.foreground
            onClicked: root.copyResult()
          }

          Button {
            visible: root.mode === "result" && !root.busy && root.resultText !== ""
            text: "Replace"
            selected: true
            foreground: root.foreground
            accent: Color.accent
            onClicked: root.replaceSelection()
          }
        }
      }
    }
  }
}