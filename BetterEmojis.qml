import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "EmojiData.js" as EmojiData

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "wessel.better-emojis"
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/" + pluginId + "/settings.json"

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var emojis: []
  property var filteredEmojis: []
  property var emojiMap: ({})
  property var emojiCategories: []
  property string activeCategory: "all"
  property bool showSettings: false
  property int settingsGroup: 0
  property int settingsOption: 0
  property var recentAdjectives: ["fun", "cute", "heartwarming", "weird", "random", "silly", "wholesome", "goofy", "cheeky", "sparkly"]
  property string recentEmptyAdjective: "fun"
  property int lastRecentAdjectiveIndex: -1

  property var settings: defaultSettings()
  property bool settingsLoaded: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int tabBarHeight: Style.space(36)
  property int contentSpacing: Style.spacing.md
  readonly property real preferredCellSize: Math.max(Style.space(28), Style.space(Number(settings.cellSize) || 46))
  readonly property int cardWidthBase: Math.max(Style.space(Number(settings.cardWidth) || 480), Style.space(320))
  readonly property int cardWidthClamped: Math.max(0, Math.min(cardWidthBase, panel.width - Style.gapsOut * 2))
  readonly property int cardWidth: {
    var inset = contentMargin * 2 + Math.max(1, Style.space(2)) * 2
    var base = cardWidthClamped
    var avail = base - inset
    if (avail < preferredCellSize) return base
    var cols = Math.floor(avail / preferredCellSize)
    if (cols < 1) cols = 1
    return Math.max(Style.space(320), cols * preferredCellSize + inset)
  }
  readonly property int cardHeight: Math.max(0, Math.min(
    Math.max(Style.space(Number(settings.cardHeight) || 560), Style.space(380)),
    panel.height - Style.gapsOut * 2
  ))
  readonly property real gridWidth: Math.max(1, cardWidth - contentMargin * 2 - Math.max(1, Style.space(2)) * 2)
  readonly property int columns: Math.max(1, Math.floor(gridWidth / preferredCellSize))
  readonly property real cellWidth: preferredCellSize
  readonly property real cellHeight: preferredCellSize
  readonly property int emojiPixelSize: Math.max(12, Math.round(preferredCellSize * 0.58))
  readonly property bool searching: filterText.length > 0
  readonly property var tabs: buildTabs()
  readonly property var emojiSizeOptions: [
    { label: "Normal", value: 46 },
    { label: "Large", value: 58 },
    { label: "Extra Large", value: 72 }
  ]
  readonly property var cardWidthOptions: [
    { label: "Normal", value: 480 },
    { label: "Wide", value: 620 },
    { label: "Extra Wide", value: 780 }
  ]
  readonly property var cardHeightOptions: [
    { label: "Normal", value: 560 },
    { label: "Tall", value: 720 },
    { label: "Extra Tall", value: 900 }
  ]

  function defaultSettings() {
    return { cellSize: 46, cardWidth: 480, cardHeight: 560, skinTone: 0, showAllTones: false, showAllGenders: false, mergeGenders: true, genderMode: 0, showRecents: true, recents: [] }
  }

  function mergedSettings(patch) {
    var next = {}
    for (var key in root.settings) next[key] = root.settings[key]
    for (var p in patch) next[p] = patch[p]
    return next
  }

  function buildTabs() {
    var icons = {
      "Smileys & Emotion": "󰱨",
      "People & Body": "󰀄",
      "Animals & Nature": "󰏩",
      "Food & Drink": "󰉚",
      "Activities": "󰠆",
      "Travel & Places": "󰀝",
      "Objects": "󰌵",
      "Symbols": "󰋑",
      "Flags": "󰈻"
    }
    var out = [{ id: "all", icon: "󰀻", label: "All" }]
    if (root.settings.showRecents !== false) out.push({ id: "recent", icon: "󰋚", label: "Recent" })
    for (var i = 0; i < root.emojiCategories.length; i++) {
      var c = root.emojiCategories[i]
      out.push({ id: c, icon: icons[c] || "•", label: c })
    }
    return out
  }

  function tabIndexFor(id) {
    for (var i = 0; i < root.tabs.length; i++) {
      if (root.tabs[i].id === id) return i
    }
    return 0
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.showSettings = false
    root.activeCategory = "all"
    Qt.callLater(function() {
      root.rebuildDisplay()
      keyCatcher.forceActiveFocus()
      tabBar.positionViewAtIndex(root.tabIndexFor(root.activeCategory), ListView.Contain)
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    flushSettings()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadEmojis(raw) {
    root.emojis = EmojiData.parseEmojis(raw)
    var map = {}
    for (var i = 0; i < root.emojis.length; i++) {
      var item = root.emojis[i]
      if (item && item.e) map[item.e] = item
    }
    root.emojiMap = map
    root.emojiCategories = EmojiData.categories(root.emojis)
    if (root.opened) Qt.callLater(function() { root.rebuildDisplay() })
  }

  function recentItems() {
    var list = Array.isArray(root.settings.recents) ? root.settings.recents : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var base = EmojiData.stripTones(list[i])
      var item = root.emojiMap[base]
      out.push(item || { e: list[i], n: "", k: "" })
    }
    return out
  }

  function genderMember(item) {
    if (!item || !item.gg) return item
    var mode = Math.max(0, Math.min(2, Number(root.settings.genderMode) || 0))
    var order = [item.gm, item.gf, item.gp]
    if (mode === 0) order = [item.gm, item.gf, item.gp]
    else if (mode === 1) order = [item.gf, item.gm, item.gp]
    else order = [item.gp, item.gm, item.gf]
    for (var i = 0; i < order.length; i++) {
      var candidate = order[i]
      if (candidate && root.emojiMap[candidate]) return root.emojiMap[candidate]
    }
    return item
  }

  function pickRecentEmptyAdjective() {
    var list = root.recentAdjectives
    if (!list || list.length === 0) return
    var idx
    do {
      idx = Math.floor(Math.random() * list.length)
    } while (list.length > 1 && idx === root.lastRecentAdjectiveIndex)
    root.lastRecentAdjectiveIndex = idx
    root.recentEmptyAdjective = list[idx]
  }

  function displayItems(items) {
    var out = []
    var seenGroups = {}
    for (var i = 0; i < items.length; i++) {
      var item = root.settings.mergeGenders ? root.genderMember(items[i]) : items[i]
      if (!item || !item.e) continue
      if (root.settings.mergeGenders && item.gg) {
        if (seenGroups[item.gg]) continue
        seenGroups[item.gg] = true
      }
      if (!root.settings.showAllTones || !item.t) {
        out.push({ item: item, preToned: false })
        continue
      }
      out.push({ item: { e: item.e, n: item.n, k: item.k, c: item.c }, preToned: true })
      for (var tone = 0; tone < 5; tone++)
        out.push({ item: { e: item.v[tone], n: item.n, k: item.k, c: item.c }, preToned: true })
    }
    return out
  }

  function rebuildDisplay() {
    var out
    if (root.searching) {
      out = EmojiData.filterEmojis(root.emojis, root.filterText, 1000)
    } else if (root.activeCategory === "recent") {
      out = recentItems()
    } else {
      out = EmojiData.filterEmojis(root.emojis, "", 1000, root.activeCategory === "all" ? "" : root.activeCategory)
    }
    var rows = root.displayItems(out)
    root.filteredEmojis = rows

    displayModel.clear()
    for (var j = 0; j < rows.length; j++) {
      var item = rows[j].item
      displayModel.append({
        emoji: item.e,
        name: item.n || "",
        toneable: !!item.t,
        variants: item._variantsStr !== undefined ? item._variantsStr : JSON.stringify(item.v || []),
        preToned: rows[j].preToned,
        index: j
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0
    Qt.callLater(function() {
      if (displayModel.count > 0)
        resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function setCursor(index) {
    if (displayModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    cursorActive = true
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      setCursor(delta < 0 ? displayModel.count - 1 : 0)
      return
    }
    setCursor((selectedIndex + delta + displayModel.count) % displayModel.count)
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      setCursor(delta < 0 ? displayModel.count - 1 : 0)
      return
    }
    var newIndex = selectedIndex + delta * columns
    setCursor(newIndex)
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      setCursor(delta < 0 ? displayModel.count - 1 : 0)
      return
    }
    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))
    setCursor(selectedIndex + delta * columns * visibleRows)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setCategory(id) {
    if (root.searching) root.setFilter("")
    if (root.activeCategory === id) return
    root.activeCategory = id
    if (id === "recent" && recentItems().length === 0) root.pickRecentEmptyAdjective()
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() {
      tabBar.positionViewAtIndex(root.tabIndexFor(id), ListView.Contain)
    })
  }

  function selectCategoryOffset(delta) {
    var count = root.tabs.length
    if (!count) return
    var index = (root.tabIndexFor(root.activeCategory) + delta + count) % count
    root.setCategory(root.tabs[index].id)
  }

  function selectTabIndex(index) {
    var count = root.tabs.length
    if (!count) return
    var wrapped = ((index % count) + count) % count
    root.setCategory(root.tabs[wrapped].id)
  }

  function activateIndex(index, copyOnly) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row.emoji, row.toneable, row.variants, row.preToned, copyOnly === true)
  }

  function applySelected(emojiChar, toneable, variants, preToned, copyOnly) {
    if (!emojiChar) return
    var str = (!preToned && toneable && Number(root.settings.skinTone) > 0)
      ? EmojiData.applySkinTone(emojiChar, root.settings.skinTone, variants)
      : emojiChar
    root.settings = root.mergedSettings({ recents: EmojiData.pushRecent(root.settings.recents, str, 30) })
    root.scheduleSave()
    root.dismiss()
    if (copyOnly) {
      Quickshell.execDetached(["wl-copy", "--type", "text/plain", str])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", str])
    }
  }

  function applySetting(key, value) {
    var patch = {}
    patch[key] = value
    root.settings = root.mergedSettings(patch)
    root.scheduleSave()
    if (key === "showAllTones" || key === "mergeGenders" || key === "genderMode") root.rebuildDisplay()
  }

  function snapToOption(value, options) {
    var best = options[0].value
    for (var i = 1; i < options.length; i++) {
      if (Math.abs(options[i].value - value) < Math.abs(best - value)) best = options[i].value
    }
    return best
  }

  function setSkinTone(tone) {
    var t = Math.max(0, Math.min(5, Number(tone) || 0))
    root.settings = root.mergedSettings({ skinTone: t })
    root.scheduleSave()
  }

  function cycleSkinTone(delta) {
    root.setSkinTone((Number(root.settings.skinTone) + delta + 6) % 6)
  }

  function cycleGender() {
    if (!root.settings.mergeGenders) return
    root.applySetting("genderMode", (Number(root.settings.genderMode) + 1) % 3)
    root.rebuildDisplay()
  }

  function clearRecents() {
    root.settings = root.mergedSettings({ recents: [] })
    root.scheduleSave()
    if (root.activeCategory === "recent") {
      root.pickRecentEmptyAdjective()
      root.rebuildDisplay()
    }
  }

  function toggleSettings() {
    root.showSettings = !root.showSettings
    Qt.callLater(function() {
      if (root.showSettings) {
        root.settingsGroup = 0
        root.settingsOption = root.settingsOptionIndex(0)
      }
      keyCatcher.forceActiveFocus()
    })
  }

  function settingsOptionCount(group) {
    if (group === 0) return root.emojiSizeOptions.length
    if (group === 1) return root.cardWidthOptions.length
    if (group === 2) return root.cardHeightOptions.length
    if (group === 3) return 6
    return 1
  }

  function settingsOptionIndex(group) {
    var value = group === 0 ? Number(root.settings.cellSize)
      : (group === 1 ? Number(root.settings.cardWidth)
      : (group === 2 ? Number(root.settings.cardHeight) : Number(root.settings.skinTone)))
    var options = group === 0 ? root.emojiSizeOptions
      : (group === 1 ? root.cardWidthOptions : root.cardHeightOptions)
    if (group === 3) return Math.max(0, Math.min(5, value))
    if (!options || !options.length) return 0
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
    return 0
  }

  function selectSettingsGroup(delta) {
    var total = root.settings.showRecents === false ? 7 : 8
    var next = root.settingsGroup
    for (var step = 0; step < total; step++) {
      next = (next + delta + total) % total
      if (next === 7 && root.settings.showRecents === false) continue
      break
    }
    root.settingsGroup = next
    root.settingsOption = root.settingsOptionIndex(root.settingsGroup)
  }

  function selectSettingsOption(delta) {
    var count = root.settingsOptionCount(root.settingsGroup)
    if (count <= 1) return
    root.settingsOption = (root.settingsOption + delta + count) % count
    if (root.settingsGroup === 0) root.applySetting("cellSize", root.emojiSizeOptions[root.settingsOption].value)
    else if (root.settingsGroup === 1) root.applySetting("cardWidth", root.cardWidthOptions[root.settingsOption].value)
    else if (root.settingsGroup === 2) root.applySetting("cardHeight", root.cardHeightOptions[root.settingsOption].value)
    else if (root.settingsGroup === 3) root.setSkinTone(root.settingsOption)
  }

  function activateSettingsGroup() {
    if (root.settingsGroup === 4) root.applySetting("showAllTones", !root.settings.showAllTones)
    else if (root.settingsGroup === 5) {
      var showAll = !root.settings.showAllGenders
      root.settings = root.mergedSettings({ showAllGenders: showAll, mergeGenders: !showAll })
      root.scheduleSave()
      root.rebuildDisplay()
    } else if (root.settingsGroup === 6) {
      var showRecents = !root.settings.showRecents
      root.settings = root.mergedSettings({ showRecents: showRecents })
      root.scheduleSave()
      if (!showRecents && root.activeCategory === "recent") root.activeCategory = "all"
      root.rebuildDisplay()
    } else if (root.settingsGroup === 7) {
      if (root.settings.showRecents !== false) root.clearRecents()
    } else root.selectSettingsOption(0)
  }

  function loadSettings(raw) {
    if (root.settingsLoaded) return
    var base = root.defaultSettings()
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (Util.isPlainObject(parsed)) {
        if (isFinite(Number(parsed.cellSize))) base.cellSize = root.snapToOption(Math.max(28, Math.min(96, Number(parsed.cellSize))), root.emojiSizeOptions)
        if (isFinite(Number(parsed.cardWidth))) base.cardWidth = root.snapToOption(Math.max(320, Math.min(900, Number(parsed.cardWidth))), root.cardWidthOptions)
        if (isFinite(Number(parsed.cardHeight))) base.cardHeight = root.snapToOption(Math.max(380, Math.min(1100, Number(parsed.cardHeight))), root.cardHeightOptions)
        if (isFinite(Number(parsed.skinTone))) base.skinTone = Math.max(0, Math.min(5, Number(parsed.skinTone)))
        if (typeof parsed.showAllTones === "boolean") base.showAllTones = parsed.showAllTones
        if (typeof parsed.showAllGenders === "boolean") {
          base.showAllGenders = parsed.showAllGenders
          base.mergeGenders = !parsed.showAllGenders
        } else if (parsed.mergeGenders === true) {
          base.mergeGenders = true
          base.showAllGenders = false
        }
        if (typeof parsed.showRecents === "boolean") base.showRecents = parsed.showRecents
        if (isFinite(Number(parsed.genderMode))) base.genderMode = Math.max(0, Math.min(2, Math.floor(Number(parsed.genderMode))))
        if (Array.isArray(parsed.recents)) {
          base.recents = parsed.recents.filter(function(e) { return typeof e === "string" && e.length > 0 }).slice(0, 30)
        }
      }
    } catch (e) {
      console.warn("better-emojis: settings parse failed:", e)
    }
    root.settings = base
    root.settingsLoaded = true
  }

  function flushSettings() {
    if (!root.settingsLoaded) return
    settingsFile.setText(JSON.stringify(root.settings))
  }

  function scheduleSave() {
    if (!root.settingsLoaded) return
    settingsSaveTimer.restart()
  }

  Component.onCompleted: {
    stateDirProc.running = true
  }

  ListModel { id: displayModel }

  Process {
    id: stateDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/plugins/" + root.pluginId]
    onExited: settingsFile.reload()
  }

  Timer {
    id: settingsSaveTimer
    interval: 250
    repeat: false
    onTriggered: root.flushSettings()
  }

  FileView {
    path: root.pluginDir + "/emojis.json"
    onLoaded: root.loadEmojis(text())
  }

  FileView {
    id: settingsFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  PanelWindow {
    id: panel
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-emojis"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
      width: root.opened ? panel.width : 0
      height: root.opened ? panel.height : 0
    }

    Shortcut {
      sequence: "Ctrl+S"
      enabled: root.opened
      onActivated: root.toggleSettings()
    }

    Shortcut {
      sequence: "Ctrl+,"
      enabled: root.opened
      onActivated: root.toggleSettings()
    }

    Shortcut {
      sequence: "Esc"
      enabled: root.opened && root.showSettings
      onActivated: root.dismiss()
    }

    Rectangle {
      anchors.fill: parent
      color: root.opened ? root.scrim : "transparent"
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      visible: root.opened
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.showSettings) root.dismiss()
            else if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (!root.showSettings && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier) === 0) {
            root.selectCategoryOffset(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.selectTabIndex(event.key - Qt.Key_1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
            root.cycleSkinTone(1)
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_G) {
            root.cycleGender()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_S || event.key === Qt.Key_Comma)) {
            root.toggleSettings()
            event.accepted = true
          } else if (root.showSettings && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            root.selectSettingsGroup(event.key === Qt.Key_Backtab ? -1 : 1)
            event.accepted = true
          } else if (root.showSettings && event.key === Qt.Key_Up) {
            root.selectSettingsGroup(-1)
            event.accepted = true
          } else if (root.showSettings && event.key === Qt.Key_Down) {
            root.selectSettingsGroup(1)
            event.accepted = true
          } else if (root.showSettings && event.key === Qt.Key_Left) {
            root.selectSettingsOption(-1)
            event.accepted = true
          } else if (root.showSettings && event.key === Qt.Key_Right) {
            root.selectSettingsOption(1)
            event.accepted = true
          } else if (root.showSettings && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.activateSettingsGroup()
            event.accepted = true
          } else if (root.showSettings) {
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex, event.modifiers & Qt.ControlModifier)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          id: header
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.right: gearButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.showSettings ? "Settings" : (root.filterText || "Search emojis…")
            color: root.foreground
            opacity: root.showSettings ? 1 : (root.filterText ? 1 : 0.58)
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Rectangle {
            id: gearButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32)
            height: Style.space(32)
            radius: root.cornerRadius
            color: gearArea.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.centerIn: parent
              text: root.showSettings ? "󰱨" : "󰒓"
              color: root.foreground
              opacity: gearArea.containsMouse ? 1 : 0.7
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.heading * 1.25)
            }

            MouseArea {
              id: gearArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleSettings()
            }
          }
        }

        ListView {
          id: tabBar
          visible: !root.showSettings
          width: parent.width
          height: root.tabBarHeight
          orientation: ListView.Horizontal
          model: root.tabs
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index

            readonly property bool isActive: !root.searching && modelData.id === root.activeCategory

            width: chipRow.implicitWidth + Style.space(16)
            height: root.tabBarHeight - Style.space(6)
            y: Style.space(3)
            radius: root.cornerRadius
            color: isActive ? root.selectedBackground : (chipArea.containsMouse ? root.selectedBackground : "transparent")
            opacity: isActive ? 1 : (chipArea.containsMouse ? 0.85 : 1)

            Row {
              id: chipRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.modelData.icon
                color: chip.isActive ? root.selectedText : root.foreground
                opacity: chip.isActive ? 1 : 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.modelData.label
                color: chip.isActive ? root.selectedText : root.foreground
                opacity: chip.isActive ? 1 : 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            MouseArea {
              id: chipArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setCategory(chip.modelData.id)
            }
          }
        }

        Item {
          id: gridArea
          visible: !root.showSettings
          width: parent.width
          height: parent.height - root.headerHeight - root.tabBarHeight - root.contentSpacing * 2

          GridView {
            id: resultGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: cell
              required property int index
              required property string emoji
              required property string name
              required property bool toneable
              required property string variants
              required property bool preToned

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: root.cellWidth
              height: root.cellHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                text: {
                  if (parent.preToned || !parent.toneable || Number(root.settings.skinTone) === 0) return parent.emoji
                  return EmojiData.applySkinTone(parent.emoji, root.settings.skinTone, parent.variants)
                }
                font.family: "Noto Color Emoji"
                font.pixelSize: root.emojiPixelSize
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              MouseArea {
                id: cellArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.activateIndex(index, false)
                }
              }
            }
          }

          Column {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              visible: !(root.activeCategory === "recent" && !root.searching)
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.searching
                ? "No matches for “" + root.filterText + "”"
                : (root.activeCategory === "recent" ? "No recent emojis yet.\nGo send someone a " + root.recentEmptyAdjective + " emoji!" : "Nothing here")
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        }

        Flickable {
          id: settingsPage
          visible: root.showSettings
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          contentWidth: width
          contentHeight: settingsContent.implicitHeight
          clip: true

          Column {
            id: settingsContent
            width: parent.width
            spacing: Style.space(12)

          PanelSectionHeader {
            text: "EMOJI SIZE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: sizeRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.emojiSizeOptions.length - 1)) / root.emojiSizeOptions.length

            Repeater {
              model: root.emojiSizeOptions

              Button {
                required property var modelData
                required property int index

                width: sizeRow.cellWidth
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                focusable: false
                active: Number(root.settings.cellSize) === modelData.value
                onClicked: root.applySetting("cellSize", modelData.value)
              }
            }
          }

          PanelSectionHeader {
            text: "WINDOW WIDTH"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: widthRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.cardWidthOptions.length - 1)) / root.cardWidthOptions.length

            Repeater {
              model: root.cardWidthOptions

              Button {
                required property var modelData
                required property int index

                width: widthRow.cellWidth
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                focusable: false
                active: Number(root.settings.cardWidth) === modelData.value
                onClicked: root.applySetting("cardWidth", modelData.value)
              }
            }
          }

          PanelSectionHeader {
            text: "WINDOW HEIGHT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: heightRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.cardHeightOptions.length - 1)) / root.cardHeightOptions.length

            Repeater {
              model: root.cardHeightOptions

              Button {
                required property var modelData
                required property int index

                width: heightRow.cellWidth
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                focusable: false
                active: Number(root.settings.cardHeight) === modelData.value
                onClicked: root.applySetting("cardHeight", modelData.value)
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
            strength: 0.3
          }

          PanelSectionHeader {
            text: "SKIN TONES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: toneRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 5) / 6

            Repeater {
              model: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]
              Button {
                required property int index
                required property string modelData
                width: toneRow.cellWidth
                text: modelData
                fontSize: Style.font.title
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: 0
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                focusable: false
                active: Number(root.settings.skinTone) === index
                onClicked: root.setSkinTone(index)
              }
            }
          }

          Toggle {
            width: parent.width
            activeFocusOnTab: false
            hasCursor: root.showSettings && root.settingsGroup === 4
            titleSize: Style.font.caption
            label: "Show all skin tones in emoji grid"
            description: ""
            checked: !!root.settings.showAllTones
            onClicked: root.applySetting("showAllTones", !root.settings.showAllTones)
          }

          Text {
            visible: !root.settings.showAllTones
            text: "Ctrl+T cycles the default tone"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator {
            foreground: root.foreground
            strength: 0.3
          }

          PanelSectionHeader {
            text: "GENDERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            activeFocusOnTab: false
            hasCursor: root.showSettings && root.settingsGroup === 5
            titleSize: Style.font.caption
            label: "Show all genders in emoji grid"
            description: ""
            checked: !!root.settings.showAllGenders
            onClicked: {
              var showAll = !root.settings.showAllGenders
              root.settings = root.mergedSettings({ showAllGenders: showAll, mergeGenders: !showAll })
              root.scheduleSave()
              root.rebuildDisplay()
            }
          }

          Text {
            visible: !!root.settings.mergeGenders
            text: "Hotkey Ctrl+G swaps the gender · active: " + ["male", "female", "person"][Math.max(0, Math.min(2, Number(root.settings.genderMode) || 0))]
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator {
            foreground: root.foreground
            strength: 0.3
          }

          PanelSectionHeader {
            text: "RECENTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            activeFocusOnTab: false
            hasCursor: root.showSettings && root.settingsGroup === 6
            titleSize: Style.font.caption
            label: "Show Recent tab"
            description: ""
            checked: !!root.settings.showRecents
            onClicked: {
              var show = !root.settings.showRecents
              root.settings = root.mergedSettings({ showRecents: show })
              root.scheduleSave()
              if (!show && root.activeCategory === "recent") root.activeCategory = "all"
              root.rebuildDisplay()
            }
          }

          Button {
            visible: !!root.settings.showRecents
            hasCursor: root.showSettings && root.settingsGroup === 7
            width: parent.width
            text: "Clear recent emojis"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            focusable: false
            onClicked: root.clearRecents()
          }
        }
      }
    }
  }
}
}
