import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "omarchy-clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  // Next Event in Bar Option
  readonly property bool showNextEvent: setting("showNextEvent", false) === true
  readonly property bool showTomorrowEvents: setting("showTomorrowEvents", false) === true
  readonly property var nextEvent: (showNextEvent && panelLoader.item && panelLoader.item.allEvents)
    ? Model.findNextEvent(panelLoader.item.allEvents, root.displayDate, root.showTomorrowEvents)
    : null
  readonly property string nextEventText: nextEvent ? Model.nextEventLabel(nextEvent, root.displayDate) : ""

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string clockNotifyBin: pluginDir + "/bin/clock-notify"

  // Notifications State & Options
  property var notifiedEventsMap: ({})
  readonly property bool enableNotifications: setting("enableNotifications", true) === true
  readonly property int notificationMinutes: parseInt(setting("notificationMinutes", 10), 10) || 10
  readonly property bool notifyAtStart: setting("notifyAtStart", true) === true
  readonly property bool persistentNotifications: setting("persistentNotifications", true) === true

  function checkNotifications() {
    if (!enableNotifications || !panelLoader.item || !panelLoader.item.allEvents) return
    var items = Model.findNotificationEvents(
      panelLoader.item.allEvents,
      root.displayDate,
      root.notificationMinutes,
      root.notifyAtStart,
      root.notifiedEventsMap
    )
    if (!items || items.length === 0) return

    var map = root.notifiedEventsMap
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      map[item.notificationKey] = true
      var glyph = item.event.meetUrl ? "󰕧" : "󰃭"
      var title = item.type === "start"
        ? ((item.event.meetUrl ? "Meeting Starting Now: " : "Event Starting Now: ") + (item.event.summary || "Event"))
        : (((item.event.meetUrl ? "Meeting in " : "Event in ") + item.diff + " min: ") + (item.event.summary || "Event"))

      var body = String(item.event.timeDisplay || "") + " · " + String(item.event.calendarName || "")
      if (item.event.location && item.event.location !== "") {
        body += "\n" + item.event.location
      }
      if (item.event.meetUrl && item.event.meetUrl !== "") {
        body += "\nClick toast to join Google Meet"
      }

      Quickshell.execDetached([
        root.clockNotifyBin,
        glyph,
        title,
        body,
        (item.event.meetUrl && Model.isValidMeetingUrl(item.event.meetUrl)) ? String(item.event.meetUrl).trim() : "",
        root.persistentNotifications ? "critical" : "normal"
      ])
    }
    root.notifiedEventsMap = map
  }

  function sendTestNotification() {
    Quickshell.execDetached([
      root.clockNotifyBin,
      "󰕧",
      "Meeting in 10 min: Team Standup",
      "09:00 - 09:30 · Work Calendar\nClick toast to join Google Meet",
      "https://meet.google.com",
      root.persistentNotifications ? "critical" : "normal"
    ])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onDisplayDateChanged: root.checkNotifications()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      if (panelLoader.item) {
        if (typeof panelLoader.item.loadCachedData === "function") panelLoader.item.loadCachedData()
        if (typeof panelLoader.item.checkAuthStatus === "function") panelLoader.item.checkAuthStatus()
      }
      Qt.callLater(root.checkNotifications)
    }
  }

  Connections {
    target: panelLoader.item
    function onAllEventsChanged() {
      root.checkNotifications()
    }
  }

  IpcHandler {
    target: "omarchy-clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void {
      if (panelLoader.item) {
        panelLoader.item.showSettings = false
        panelLoader.item.showAddEvent = false
      }
      root.open()
    }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function openSettings(): void {
      root.open()
      if (panelLoader.item) {
        panelLoader.item.showAddEvent = false
        panelLoader.item.showSettings = true
      }
    }
    function openAddEvent(): void {
      root.open()
      if (panelLoader.item) {
        panelLoader.item.showSettings = false
        panelLoader.item.showAddEvent = true
      }
    }
  }

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void {
      if (panelLoader.item) {
        panelLoader.item.showSettings = false
        panelLoader.item.showAddEvent = false
      }
      root.open()
    }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function openSettings(): void {
      root.open()
      if (panelLoader.item) {
        panelLoader.item.showAddEvent = false
        panelLoader.item.showSettings = true
      }
    }
    function openAddEvent(): void {
      root.open()
      if (panelLoader.item) {
        panelLoader.item.showSettings = false
        panelLoader.item.showAddEvent = true
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.vertical || (root.showNextEvent && root.nextEventText !== "")) ? "" : root.displayText
    labelVisible: !root.vertical && !(root.showNextEvent && root.nextEventText !== "")
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : (text !== "" || (root.showNextEvent && root.nextEventText !== ""))
    fixedWidth: (!root.vertical && root.showNextEvent && root.nextEventText !== "")
      ? Math.round(nextEventRow.implicitWidth + Style.spaceReal(button.horizontalMargin) * 2)
      : -1
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.nextEvent
      ? (String(root.nextEvent.summary || "") + " (" + (root.nextEvent.allDay ? "All day" : String(root.nextEvent.timeDisplay || "")) + " · " + String(root.nextEvent.calendarName || "") + ")")
      : ""

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.cycleFormat()
      } else if (b === Qt.MiddleButton) {
        if (root.nextEvent && root.nextEvent.meetUrl && Model.isValidMeetingUrl(root.nextEvent.meetUrl)) {
          Quickshell.execDetached(["xdg-open", "--", String(root.nextEvent.meetUrl).trim()])
        } else if (root.bar) {
          root.bar.run("omarchy-menu-timezone")
        }
      } else {
        root.togglePanel()
      }
    }

    // Horizontal Layout with Next Event Countdown (Consistent Bar Styling, No Color Divergence)
    Row {
      id: nextEventRow
      visible: !root.vertical && root.showNextEvent && root.nextEventText !== ""
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: Style.space(12)
        color: button.foreground
        opacity: 0.3
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          visible: !!(root.nextEvent && root.nextEvent.meetUrl !== "")
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕧"
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          textFormat: Text.PlainText
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.nextEventText
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          maximumLineCount: 1
          textFormat: Text.PlainText
        }
      }
    }

    // Vertical Stack Layout
    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
