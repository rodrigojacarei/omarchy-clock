import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "rodrigo.clock"
  ipcTarget: "rodrigo.clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today & Selection State
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property int currentMinutes: today.getHours() * 60 + today.getMinutes()

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  property string selectedDateKey: todayKey
  readonly property date selectedDate: {
    var parts = (selectedDateKey || todayKey).split("-")
    if (parts.length === 3) {
      return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10))
    }
    return today
  }

  // ---- Year Progress
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int currentWeekNumber: Model.isoWeek(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int selectedWeekNumber: Model.isoWeek(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate())

  // ---- Week convention
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)

  // ---- Google Calendar, Local & Cloud Events Data
  property bool showSettings: false
  property bool showAddEvent: false
  property var pendingDeleteEvent: null
  onShowAddEventChanged: {
    if (showAddEvent) {
      newEventCol.addMeetingLink = false
      newEventCol.isRecurring = false
      newEventCol.customFreq = "WEEKLY"
      newEventCol.customInterval = 1
      newEventCol.customWeekdays = [Model.weekdayCodeForDate(root.selectedDate)]
      newEventCol.customMonthlyType = "dayOfMonth"
      newEventCol.customMonthDay = root.selectedDate ? root.selectedDate.getDate() : 1
      newEventCol.customNthIndex = root.selectedDate ? (Math.floor((root.selectedDate.getDate() - 1) / 7) + 1) : 1
      newEventCol.customNthWeekday = Model.weekdayCodeForDate(root.selectedDate)
      newEventCol.customEndType = "never"
      newEventCol.customCount = 10
    }
  }
  property var calendars: []
  property var cloudCalendars: []
  property var disabledCalendarIds: []
  property var localEvents: []
  property var cloudApiEvents: []
  property var rawCalendarIcs: ({})
  property var allEvents: []
  property var eventsByDate: ({})
  property bool syncing: false
  property string syncStatusText: ""
  property int syncIndex: 0
  property var syncQueue: []

  // OAuth 2.0 Cloud State
  property bool isCloudConnected: false
  property bool hasClientCredentials: false
  property bool showClientConfig: false
  property string currentAuthUrl: ""
  property bool isWaitingAuth: false

  readonly property var gridRange: Model.gridDateRange(viewYear, viewMonth, weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, eventsByDate)
  readonly property bool hidePastEvents: setting("hidePastEvents", false) === true
  readonly property bool showTomorrowEvents: setting("showTomorrowEvents", false) === true

  readonly property date tomorrowDate: new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)
  readonly property string tomorrowKey: Model.keyForDate(tomorrowDate)
  readonly property var tomorrowEvents: eventsByDate[tomorrowKey] || []

  readonly property var selectedEvents: {
    var list = eventsByDate[selectedDateKey] || []
    if (!hidePastEvents || selectedDateKey !== todayKey) return list

    var filtered = []
    var curMin = root.currentMinutes

    for (var i = 0; i < list.length; i++) {
      var ev = list[i]
      if (!ev) continue
      if (ev.allDay) {
        filtered.push(ev)
        continue
      }
      var startParts = (ev.startTime || "00:00").split(":")
      var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)
      var endMin = startMin + 30
      if (ev.endTime) {
        var endParts = ev.endTime.split(":")
        var calcEnd = parseInt(endParts[0], 10) * 60 + parseInt(endParts[1] || "0", 10)
        if (calcEnd > startMin) endMin = calcEnd
      }
      if (endMin > curMin) {
        filtered.push(ev)
      }
    }
    return filtered
  }

  readonly property var writableCalendars: {
    var list = []
    if (cloudCalendars && Array.isArray(cloudCalendars)) {
      for (var i = 0; i < cloudCalendars.length; i++) {
        var c = cloudCalendars[i]
        if (c && (c.accessRole === "owner" || c.accessRole === "writer" || !c.accessRole)) {
          if (!root.isCalendarDisabled(c.id)) {
            list.push(c)
          }
        }
      }
    }
    return list
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string gcalSyncBin: pluginDir + "/bin/gcal-sync"
  readonly property string clockNotifyBin: pluginDir + "/bin/clock-notify"

  // Palette & typography
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // ---- Lifecycle & Navigation
  Component.onCompleted: {
    loadCachedData()
    checkAuthStatus()
  }

  function open() {
    refresh()
    loadCachedData()
    checkAuthStatus()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    showSettings = false
    showAddEvent = false
    pendingDeleteEvent = null
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    if (!root.selectedDateKey) root.selectedDateKey = root.todayKey
    syncAllCalendars()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedDateKey = todayKey
  }

  function selectDate(key) {
    root.selectedDateKey = key
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    recomputeExpandedEvents()
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Persistence & Sync
  function loadCachedData() {
    loadConfigProc.running = true
  }

  function checkAuthStatus() {
    authStatusProc.running = true
  }

  function safePayload(str, limit) {
    var s = String(str || "")
    var maxLen = limit || 5242880
    if (s.length > maxLen) {
      return s.substring(0, maxLen)
    }
    return s
  }

  function startGoogleAuth() {
    root.isWaitingAuth = true
    startAuthProc.running = false
    startAuthProc.running = true
    if (root.currentAuthUrl && Model.isValidGoogleAuthUrl(root.currentAuthUrl)) {
      Quickshell.execDetached(["xdg-open", "--", root.currentAuthUrl])
    }
  }

  function logoutGoogle() {
    logoutProc.running = true
  }

  function setCredentials(cId, cSecret) {
    setCredsProc.stdinEnabled = true
    setCredsProc.payload = safePayload(JSON.stringify({
      client_id: String(cId || "").trim(),
      client_secret: String(cSecret || "").trim()
    }), 65536)
    setCredsProc.running = false
    setCredsProc.running = true
  }

  function saveCalendars() {
    saveCalendarsProc.stdinEnabled = true
    saveCalendarsProc.payload = safePayload(JSON.stringify(root.calendars))
    saveCalendarsProc.running = false
    saveCalendarsProc.running = true
  }

  function saveLocalEvents() {
    saveLocalEventsProc.stdinEnabled = true
    saveLocalEventsProc.payload = safePayload(JSON.stringify(root.localEvents))
    saveLocalEventsProc.running = false
    saveLocalEventsProc.running = true
  }

  function isCalendarDisabled(calId) {
    if (!calId || !root.disabledCalendarIds || !Array.isArray(root.disabledCalendarIds)) return false
    var target = String(calId).trim()
    for (var i = 0; i < root.disabledCalendarIds.length; i++) {
      var d = String(root.disabledCalendarIds[i] || "").trim()
      if (d && (d === target || target.indexOf(d) !== -1 || d.indexOf(target) !== -1)) {
        return true
      }
    }
    return false
  }

  function toggleCalendarVisibility(calId) {
    var list = root.disabledCalendarIds ? root.disabledCalendarIds.slice() : []
    var idx = list.indexOf(calId)
    if (idx !== -1) {
      list.splice(idx, 1)
    } else {
      list.push(calId)
    }
    root.disabledCalendarIds = list
    saveDisabledCalendars()
    recomputeExpandedEvents()
  }

  function saveDisabledCalendars() {
    saveDisabledCalendarsProc.stdinEnabled = true
    saveDisabledCalendarsProc.payload = safePayload(JSON.stringify(root.disabledCalendarIds))
    saveDisabledCalendarsProc.running = false
    saveDisabledCalendarsProc.running = true
  }

  function addEvent(summary, dateKey, allDay, startTime, endTime, color, calendarName, location, description, calendarId, rrule, addMeet) {
    var cleanSummary = String(summary || "").trim() || "Untitled Event"
    var cleanDateKey = String(dateKey || root.selectedDateKey)
    var cleanColor = String(color || Color.accent)
    var cleanCalName = String(calendarName || "").trim() || (root.isCloudConnected ? "Google Calendar" : "My Events")
    var cleanLoc = String(location || "").trim()
    var cleanDesc = String(description || "").trim()
    var targetCalId = String(calendarId || "primary")
    var cleanRrule = String(rrule || "").trim()
    var shouldAddMeet = !!addMeet

    if (root.isCloudConnected) {
      createCloudEventProc.stdinEnabled = true
      createCloudEventProc.payload = safePayload(JSON.stringify({
        summary: cleanSummary,
        date_key: cleanDateKey,
        all_day: allDay ? true : false,
        start: String(startTime || "09:00").trim(),
        end: String(endTime || "10:00").trim(),
        location: cleanLoc,
        description: cleanDesc,
        cal_id: targetCalId,
        rrule: cleanRrule,
        add_meet: shouldAddMeet
      }))
      createCloudEventProc.running = false
      createCloudEventProc.running = true
    } else {
      var genMeet = shouldAddMeet ? Model.generateMeetUrl() : ""
      var finalMeet = Model.extractMeetUrl(cleanLoc) || Model.extractMeetUrl(cleanDesc) || genMeet
      var newEv = {
        id: "ev_" + Date.now(),
        summary: cleanSummary,
        dateKey: cleanDateKey,
        allDay: !!allDay,
        startTime: String(startTime || "09:00").trim(),
        endTime: String(endTime || "10:00").trim(),
        calendarColor: cleanColor,
        calendarName: cleanCalName,
        location: cleanLoc,
        description: cleanDesc,
        meetUrl: finalMeet,
        isLocal: true,
        isCloud: false
      }
      var list = root.localEvents ? root.localEvents.slice() : []
      list.push(newEv)
      root.localEvents = list
      saveLocalEvents()
    }

    root.showAddEvent = false
    recomputeExpandedEvents()
  }

  function requestDeleteEvent(ev) {
    if (!ev) return
    if (ev.isRecurring) {
      root.pendingDeleteEvent = ev
    } else {
      root.deleteEvent(ev.id, !!ev.isCloud, ev.calendarId)
    }
  }

  function executeRecurringDelete(ev, scope) {
    if (!ev) return
    if (ev.isCloud && root.isCloudConnected) {
      if (scope === "this_only") {
        deleteCloudEventProc.stdinEnabled = true
        deleteCloudEventProc.payload = safePayload(JSON.stringify({
          event_id: String(ev.id),
          cal_id: String(ev.calendarId || "primary")
        }), 65536)
        deleteCloudEventProc.running = false
        deleteCloudEventProc.running = true
      } else if (scope === "following") {
        var masterId = ev.recurringEventId || ev.masterId || ev.id
        stopCloudRecurProc.stdinEnabled = true
        stopCloudRecurProc.payload = safePayload(JSON.stringify({
          master_event_id: String(masterId),
          date_key: String(ev.dateKey),
          cal_id: String(ev.calendarId || "primary")
        }), 65536)
        stopCloudRecurProc.running = false
        stopCloudRecurProc.running = true
      } else if (scope === "all_series") {
        var mId = ev.recurringEventId || ev.masterId || ev.id
        deleteCloudEventProc.stdinEnabled = true
        deleteCloudEventProc.payload = safePayload(JSON.stringify({
          event_id: String(mId),
          cal_id: String(ev.calendarId || "primary")
        }), 65536)
        deleteCloudEventProc.running = false
        deleteCloudEventProc.running = true
      }
    } else {
      var locMasterId = ev.masterId || ev.uid || ev.id
      var list = root.localEvents ? root.localEvents.slice() : []
      if (scope === "this_only") {
        for (var i = 0; i < list.length; i++) {
          if (list[i].id === locMasterId || list[i].id === ev.id) {
            var ex = list[i].exdates ? list[i].exdates.slice() : []
            if (ex.indexOf(ev.dateKey) === -1) ex.push(ev.dateKey)
            list[i].exdates = ex
          }
        }
        root.localEvents = list
        saveLocalEvents()
      } else if (scope === "following") {
        for (var j = 0; j < list.length; j++) {
          if (list[j].id === locMasterId || list[j].id === ev.id) {
            list[j].rrule = Model.stopRRuleBefore(list[j].rrule, ev.dateKey)
          }
        }
        root.localEvents = list
        saveLocalEvents()
      } else if (scope === "all_series") {
        var filtered = []
        for (var k = 0; k < list.length; k++) {
          if (list[k].id !== locMasterId && list[k].id !== ev.id) {
            filtered.push(list[k])
          }
        }
        root.localEvents = filtered
        saveLocalEvents()
      }
    }
    recomputeExpandedEvents()
  }

  function deleteEvent(eventId, isCloud, calendarId) {
    if (isCloud && root.isCloudConnected) {
      deleteCloudEventProc.stdinEnabled = true
      deleteCloudEventProc.payload = safePayload(JSON.stringify({
        event_id: String(eventId),
        cal_id: String(calendarId || "primary")
      }), 65536)
      deleteCloudEventProc.running = false
      deleteCloudEventProc.running = true
    }

    var list = []
    for (var i = 0; i < root.localEvents.length; i++) {
      if (root.localEvents[i].id !== eventId) {
        list.push(root.localEvents[i])
      }
    }
    root.localEvents = list
    saveLocalEvents()

    var cloudList = []
    for (var j = 0; j < root.cloudApiEvents.length; j++) {
      if (root.cloudApiEvents[j].id !== eventId) {
        cloudList.push(root.cloudApiEvents[j])
      }
    }
    root.cloudApiEvents = cloudList

    recomputeExpandedEvents()
  }

  function addCalendar(name, url, color) {
    var cleanUrl = Model.normalizeIcsUrl(url)
    if (!cleanUrl) return

    var cleanName = String(name || "").trim() || "Google Calendar"
    var cleanColor = String(color || "").trim() || Model.PRESET_COLORS[root.calendars.length % Model.PRESET_COLORS.length]

    var newCal = {
      id: "cal_" + Date.now(),
      name: cleanName,
      url: cleanUrl,
      color: cleanColor,
      enabled: true
    }

    var list = root.calendars ? root.calendars.slice() : []
    list.push(newCal)
    root.calendars = list
    saveCalendars()
    syncAllCalendars()
  }

  function removeCalendar(calId) {
    var list = []
    for (var i = 0; i < root.calendars.length; i++) {
      if (root.calendars[i].id !== calId) list.push(root.calendars[i])
    }
    root.calendars = list
    saveCalendars()
    recomputeExpandedEvents()
  }

  function syncAllCalendars() {
    // If Google Cloud connected, fetch cloud events via API
    if (root.isCloudConnected) {
      fetchCloudEventsProc.running = true
    }

    if (root.syncing || !root.calendars || root.calendars.length === 0) return
    var queue = []
    for (var i = 0; i < root.calendars.length; i++) {
      var cal = root.calendars[i]
      if (cal.enabled !== false && cal.url) {
        queue.push(cal)
      }
    }
    if (queue.length === 0) return

    root.syncQueue = queue
    root.syncIndex = 0
    root.syncing = true
    root.syncStatusText = "Syncing calendars..."
    syncNextCalendar()
  }

  function syncNextCalendar() {
    if (root.syncIndex >= root.syncQueue.length) {
      root.syncing = false
      var now = new Date()
      var hr = now.getHours()
      var min = now.getMinutes()
      root.syncStatusText = "Synced at " + (hr < 10 ? "0" : "") + hr + ":" + (min < 10 ? "0" : "") + min
      recomputeExpandedEvents()
      saveEventsCache()
      return
    }

    var currentCal = root.syncQueue[root.syncIndex]
    var safeUrl = Model.normalizeIcsUrl(currentCal.url)
    if (!safeUrl) {
      root.syncIndex++
      syncNextCalendar()
      return
    }

    fetchIcsProc.calendarMeta = currentCal
    fetchIcsProc.stdinEnabled = true
    fetchIcsProc.payload = safePayload(safeUrl, 4096)
    fetchIcsProc.running = false
    fetchIcsProc.running = true
  }

  function recomputeExpandedEvents() {
    var rawCombined = []
    var range = Model.gridDateRange(viewYear, viewMonth, weekStart)

    // 1. Google Cloud API Events (Highest priority)
    if (root.cloudApiEvents && Array.isArray(root.cloudApiEvents)) {
      var parsedCloud = Model.parseGoogleApiEvents(root.cloudApiEvents, Color.accent)
      for (var k = 0; k < parsedCloud.length; k++) {
        var cev = parsedCloud[k]
        if (root.isCalendarDisabled(cev.calendarId) || root.isCalendarDisabled(cev.calendarName)) continue
        if (cev.dateKey >= range.minKey && cev.dateKey <= range.maxKey) {
          rawCombined.push(cev)
        }
      }
    }

    // 2. Google Calendar iCal feeds
    var allIcsRaw = []
    for (var c = 0; c < root.calendars.length; c++) {
      var cal = root.calendars[c]
      if (cal.enabled === false) continue
      var icsText = root.rawCalendarIcs[cal.id]
      if (icsText) {
        var parsed = Model.parseIcs(icsText, { name: cal.name, color: cal.color })
        for (var p = 0; p < parsed.length; p++) {
          allIcsRaw.push(parsed[p])
        }
      }
    }
    var expandedIcs = Model.expandEvents(allIcsRaw, range.minKey, range.maxKey, false)
    for (var i = 0; i < expandedIcs.length; i++) {
      rawCombined.push(expandedIcs[i])
    }

    // 3. Local Events
    if (root.localEvents && Array.isArray(root.localEvents)) {
      var allLocalRaw = []
      for (var l = 0; l < root.localEvents.length; l++) {
        var lev = root.localEvents[l]
        if (!lev || !lev.dateKey) continue
        if (lev.rrule) {
          var p = lev.dateKey.split("-")
          var sDt = lev.allDay
            ? new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
            : new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10), parseInt((lev.startTime || "09:00").split(":")[0], 10), parseInt((lev.startTime || "09:00").split(":")[1] || "0", 10))
          var eDt = lev.allDay
            ? new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
            : new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10), parseInt((lev.endTime || "10:00").split(":")[0], 10), parseInt((lev.endTime || "10:00").split(":")[1] || "0", 10))
          allLocalRaw.push({
            uid: lev.id,
            id: lev.id,
            summary: lev.summary || "Untitled Event",
            description: lev.description || "",
            location: lev.location || "",
            meetUrl: lev.meetUrl || Model.extractMeetUrl(lev.location) || Model.extractMeetUrl(lev.description),
            calendarName: lev.calendarName || "My Events",
            calendarColor: lev.calendarColor || Color.accent,
            dtstart: { date: sDt, allDay: !!lev.allDay, key: lev.dateKey },
            dtend: { date: eDt, allDay: !!lev.allDay, key: lev.dateKey },
            rrule: lev.rrule.replace(/^RRULE:/i, ""),
            exdates: lev.exdates || [],
            isLocal: true,
            isCloud: false
          })
        } else {
          if (lev.dateKey >= range.minKey && lev.dateKey <= range.maxKey) {
            rawCombined.push({
              id: lev.id || ("local_" + l),
              uid: lev.id || ("local_" + l),
              masterId: lev.id || ("local_" + l),
              summary: lev.summary || "Untitled Event",
              description: lev.description || "",
              location: lev.location || "",
              meetUrl: lev.meetUrl || Model.extractMeetUrl(lev.location) || Model.extractMeetUrl(lev.description),
              calendarName: lev.calendarName || "My Events",
              calendarColor: lev.calendarColor || Color.accent,
              allDay: !!lev.allDay,
              dateKey: lev.dateKey,
              startTime: lev.allDay ? "00:00" : (lev.startTime || "09:00"),
              endTime: lev.allDay ? "23:59" : (lev.endTime || "10:00"),
              timeDisplay: lev.allDay ? "All day" : (lev.startTime ? (lev.startTime + (lev.endTime ? " - " + lev.endTime : "")) : "Scheduled"),
              isLocal: true,
              isCloud: false,
              isRecurring: false
            })
          }
        }
      }
      var expandedLocal = Model.expandEvents(allLocalRaw, range.minKey, range.maxKey, false)
      for (var el = 0; el < expandedLocal.length; el++) {
        expandedLocal[el].isLocal = true
        expandedLocal[el].isCloud = false
        expandedLocal[el].isRecurring = true
        expandedLocal[el].masterId = expandedLocal[el].uid || expandedLocal[el].id
        rawCombined.push(expandedLocal[el])
      }
    }

    // 4. Smart Deduplication
    var seenKeys = {}
    var deduped = []
    for (var d = 0; d < rawCombined.length; d++) {
      var item = rawCombined[d]
      if (!item || !item.dateKey) continue

      var cleanSumm = String(item.summary || "").toLowerCase().replace(/\s+/g, " ").trim()
      var sig = cleanSumm + "|" + item.dateKey + "|" + (item.startTime || "")
      if (seenKeys[sig]) continue
      seenKeys[sig] = true

      if (item.id && seenKeys[item.id]) continue
      if (item.id) seenKeys[item.id] = true

      deduped.push(item)
    }

    // 5. Sort by date and start time
    deduped.sort(function(a, b) {
      if (a.dateKey !== b.dateKey) return a.dateKey.localeCompare(b.dateKey)
      if (a.allDay && !b.allDay) return -1
      if (!a.allDay && b.allDay) return 1
      return (a.startTime || "").localeCompare(b.startTime || "")
    })

    root.allEvents = deduped
    root.eventsByDate = Model.groupEventsByDate(deduped)
  }

  function saveEventsCache() {
    saveIcsCacheProc.stdinEnabled = true
    saveIcsCacheProc.payload = safePayload(JSON.stringify(root.rawCalendarIcs))
    saveIcsCacheProc.running = false
    saveIcsCacheProc.running = true
  }

  function openGoogleCalendar() {
    Quickshell.execDetached(["xdg-open", "--", "https://calendar.google.com"])
  }

  function openMeetLink(meetUrl) {
    if (meetUrl && Model.isValidMeetingUrl(meetUrl)) {
      Quickshell.execDetached(["xdg-open", "--", String(meetUrl).trim()])
    }
  }

  function sendTestNotification() {
    Quickshell.execDetached([
      root.clockNotifyBin,
      "󰕧",
      "Meeting in 10 min: Team Standup",
      "09:00 - 09:30 · Work Calendar\nClick toast to join Google Meet",
      "https://meet.google.com",
      root.setting("persistentNotifications", true) === true ? "critical" : "normal"
    ])
  }

  // ---- Processes & Timers
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      var prevKey = root.todayKey
      root.today = clock.date
      if (root.viewingCurrentMonth && prevKey !== Model.keyForDate(clock.date)) {
        root.goToToday()
      }
    }
  }

  Timer {
    id: autoSyncTimer
    interval: (parseInt(root.setting("syncIntervalMinutes", 2), 10) || 2) * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.syncAllCalendars()
  }

  // Check OAuth Status Process
  Process {
    id: authStatusProc
    command: ["python3", root.gcalSyncBin, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) {
          try {
            var st = JSON.parse(raw)
            root.isCloudConnected = !!st.is_authenticated
            root.hasClientCredentials = !!st.has_client
          } catch (e) {}
        }
      }
    }
  }

  // Start Browser OAuth Flow Process
  Process {
    id: startAuthProc
    command: ["python3", root.gcalSyncBin, "auth"]
    stdout: StdioCollector {
      waitForEnd: false
      onStreamFinished: {
        var raw = String(text || "")
        if (raw.indexOf("AUTH_URL:") !== -1) {
          var lines = raw.split("\n")
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("AUTH_URL:") === 0) {
              var u = lines[i].substring(9).trim()
              if (Model.isValidGoogleAuthUrl(u)) {
                root.currentAuthUrl = u
                Quickshell.execDetached(["xdg-open", "--", u])
              }
            }
          }
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.isWaitingAuth = false
      Qt.callLater(function() {
        root.checkAuthStatus()
        root.syncAllCalendars()
      })
    }
  }

  // Logout Process
  Process {
    id: logoutProc
    command: ["python3", root.gcalSyncBin, "logout"]
    onExited: function(exitCode, exitStatus) {
      root.isCloudConnected = false
      root.cloudApiEvents = []
      root.recomputeExpandedEvents()
    }
  }

  // Set Client Credentials Process (payload via stdin)
  Process {
    id: setCredsProc
    command: ["python3", root.gcalSyncBin, "set-credentials"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
      root.checkAuthStatus()
      root.showClientConfig = false
    }
  }

  // Save Calendars Process (payload via stdin)
  Process {
    id: saveCalendarsProc
    command: ["python3", root.gcalSyncBin, "save-calendars"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
    }
  }

  // Save Local Events Process (payload via stdin)
  Process {
    id: saveLocalEventsProc
    command: ["python3", root.gcalSyncBin, "save-local-events"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
    }
  }

  // Save Disabled Calendars Process (payload via stdin)
  Process {
    id: saveDisabledCalendarsProc
    command: ["python3", root.gcalSyncBin, "save-disabled-calendars"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
    }
  }

  // Save ICS Cache Process (payload via stdin)
  Process {
    id: saveIcsCacheProc
    command: ["python3", root.gcalSyncBin, "save-ics-cache"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
    }
  }

  // Fetch Cloud Events Process
  Process {
    id: fetchCloudEventsProc
    command: ["python3", root.gcalSyncBin, "list-cloud"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) {
          try {
            var parsed = JSON.parse(raw)
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              if (Array.isArray(parsed.calendars)) {
                root.cloudCalendars = parsed.calendars
              }
              if (Array.isArray(parsed.events)) {
                root.cloudApiEvents = parsed.events
              }
            } else if (Array.isArray(parsed)) {
              root.cloudApiEvents = parsed
            }
            root.recomputeExpandedEvents()
          } catch (e) {}
        }
      }
    }
  }

  // Create Cloud Event Process (payload via stdin)
  Process {
    id: createCloudEventProc
    command: ["python3", root.gcalSyncBin, "create"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
      Qt.callLater(function() {
        root.syncAllCalendars()
      })
    }
  }

  // Delete Cloud Event Process (payload via stdin)
  Process {
    id: deleteCloudEventProc
    command: ["python3", root.gcalSyncBin, "delete"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
      Qt.callLater(function() {
        root.syncAllCalendars()
      })
    }
  }

  // Stop Cloud Recurrence Process (payload via stdin)
  Process {
    id: stopCloudRecurProc
    command: ["python3", root.gcalSyncBin, "stop-recurrence"]
    stdinEnabled: true
    property string payload: ""
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
      Qt.callLater(function() {
        root.syncAllCalendars()
      })
    }
  }

  // Fetch iCal Feed Process (URL via stdin, SSRF protected in Python)
  Process {
    id: fetchIcsProc
    property var calendarMeta: null
    property string payload: ""
    command: ["python3", root.gcalSyncBin, "fetch-ical"]
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      stdinEnabled = true
      Qt.callLater(function() {
        root.syncIndex++
        root.syncNextCalendar()
      })
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw.length > 0 && raw.length <= 5242880 && fetchIcsProc.calendarMeta && raw.indexOf("BEGIN:VCALENDAR") !== -1) {
          var calId = fetchIcsProc.calendarMeta.id
          var map = root.rawCalendarIcs || ({})
          map[calId] = raw
          root.rawCalendarIcs = map
        }
      }
    }
  }

  // Load Initial Config Process
  Process {
    id: loadConfigProc
    command: ["python3", root.gcalSyncBin, "load-all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) {
          try {
            var data = JSON.parse(raw)
            if (Array.isArray(data.calendars)) root.calendars = data.calendars
            if (Array.isArray(data.localEvents)) root.localEvents = data.localEvents
            if (Array.isArray(data.disabledCalendars)) root.disabledCalendarIds = data.disabledCalendars
            if (Array.isArray(data.cloudCalendars)) root.cloudCalendars = data.cloudCalendars
            if (Array.isArray(data.cloudApiEvents)) root.cloudApiEvents = data.cloudApiEvents
            if (data.rawCalendarIcs && typeof data.rawCalendarIcs === "object") {
              root.rawCalendarIcs = data.rawCalendarIcs
            }
            root.recomputeExpandedEvents()
            root.syncAllCalendars()
          } catch (e) {}
        }
      }
    }
  }

  // ---- Main Panel Layout
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: {
        if (root.pendingDeleteEvent) root.pendingDeleteEvent = null
        else if (root.showAddEvent) root.showAddEvent = false
        else if (root.showSettings) root.showSettings = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "s" || t === "S") root.showSettings = !root.showSettings
        else if (t === "n" || t === "N" || t === "+") root.showAddEvent = !root.showAddEvent
        else if (t === "r" || t === "R") root.syncAllCalendars()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: mainColumn.width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: mainColumn
          width: Math.max(calendarScroll.width, Style.space(520))
          spacing: Style.space(12)

          // ==========================================
          // TOP HEADER / HERO SECTION
          // ==========================================
          Item {
            width: parent.width
            height: heroRow.height + Style.space(4)

            // Left: Today Date & Back to Today
            Row {
              id: heroRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 38
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  id: heroDate
                  text: Qt.formatDate(root.today, "MMMM d")
                  color: heroMouse.containsMouse
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: 32
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: Qt.formatDate(root.today, "dddd, yyyy") + " · Week " + root.currentWeekNumber
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                }
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth || root.selectedDateKey !== root.todayKey
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }

            // Right: Action Buttons (Settings, Sync, Open GCal)
            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              // Sync Button
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: root.syncing ? "Syncing..." : "Sync Calendars"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: !root.syncing
                onClicked: root.syncAllCalendars()

                RotationAnimation on rotation {
                  running: root.syncing
                  loops: Animation.Infinite
                  from: 0
                  to: 360
                  duration: 1000
                }
              }

              // Open Google Calendar in Browser
              PanelActionButton {
                iconText: "󰌷"
                tooltipText: "Open Google Calendar in Browser"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.openGoogleCalendar()
              }

              // Toggle Settings View
              PanelActionButton {
                iconText: root.showSettings ? "󰅖" : "󰒓"
                tooltipText: root.showSettings ? "Back to Calendar" : "Calendar & Google Account Settings"
                foreground: root.showSettings ? Color.accent : root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.showSettings = !root.showSettings
                  if (root.showSettings) {
                    root.showAddEvent = false
                    root.checkAuthStatus()
                  }
                }
              }
            }
          }

          // ==========================================
          // YEAR PROGRESS BAR
          // ==========================================
          Item {
            width: parent.width
            height: yearBlock.height

            Item {
              id: yearBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(32)
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              Text {
                textFormat: Text.PlainText
                id: yearLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear() + " · Week " + root.currentWeekNumber + "/52"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 0.5
              }

              Text {
                textFormat: Text.PlainText
                id: yearPercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ==========================================
          // VIEW 1: CALENDAR & AGENDA VIEW
          // ==========================================
          Column {
            visible: !root.showSettings
            width: parent.width
            spacing: Style.space(12)

            // Month Grid Container
            Item {
              width: parent.width
              height: gridColumn.y + gridColumn.height

              WheelHandler {
                onWheel: function(event) {
                  if (event.angleDelta.y === 0) return
                  root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
                }
              }

              Column {
                id: gridColumn
                y: Style.space(6)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)

                // Weekday Header
                Row {
                  id: headerRow
                  spacing: root.cellSpacing

                  Rectangle {
                    width: root.weekColumnWidth
                    height: Style.space(16)
                    radius: Style.cornerRadius
                    color: weekStartMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : "transparent"

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "W"
                      color: weekStartMouse.containsMouse
                        ? Style.hoverStateColor(root.contentForeground, Color.accent)
                        : Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }

                    MouseArea {
                      id: weekStartMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleWeekStart()
                    }

                    PanelToolTip {
                      visible: weekStartMouse.containsMouse
                      text: "Start weeks on " + root.nextWeekStartLabel
                      fontFamily: root.contentFontFamily
                    }
                  }

                  Item {
                    width: root.gutterWidth
                    height: Style.space(16)
                  }

                  Repeater {
                    model: root.weekdays

                    Text {
                      textFormat: Text.PlainText
                      required property var modelData
                      width: root.cellWidth
                      height: Style.space(16)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: root.weekdayLabel(modelData)
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }
                  }
                }

                // 6 Weeks of Days
                Repeater {
                  model: root.weeks

                  Row {
                    required property var modelData
                    spacing: root.cellSpacing

                    Text {
                      textFormat: Text.PlainText
                      width: root.weekColumnWidth
                      height: root.cellHeight
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: modelData.week
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Item {
                      width: root.gutterWidth
                      height: root.cellHeight
                    }

                    Repeater {
                      model: modelData.days

                      Rectangle {
                        id: dayCell
                        required property var modelData

                        readonly property bool isSelected: root.selectedDateKey === modelData.key
                        readonly property bool isToday: modelData.today

                        width: root.cellWidth
                        height: root.cellHeight
                        radius: Style.cornerRadius

                        color: isSelected
                          ? Style.selectedFillFor(root.contentForeground, Color.accent)
                          : (cellMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")

                        border.width: isToday ? Style.spacing.hairline : (isSelected ? 1 : 0)
                        border.color: isSelected ? Color.accent : Style.normalBorderFor(root.contentForeground, Color.accent)

                        MouseArea {
                          id: cellMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.selectDate(dayCell.modelData.key)
                        }

                        Column {
                          anchors.centerIn: parent
                          spacing: 2

                          Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCell.modelData.day
                            color: dayCell.isSelected
                              ? (Color.accent)
                              : (dayCell.modelData.inMonth
                                  ? (dayCell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                                  : Qt.darker(root.contentForeground, 2.2))
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.body
                            font.bold: dayCell.isToday || dayCell.isSelected
                          }

                          // Event Indicator Dots
                          Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2
                            visible: dayCell.modelData.hasEvents

                            Repeater {
                              model: dayCell.modelData.eventColors

                              Rectangle {
                                required property var modelData
                                width: 4
                                height: 4
                                radius: 2
                                color: String(modelData || Color.accent)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Hairline down the week-number gutter
              Rectangle {
                x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
                y: gridColumn.y + headerRow.height + gridColumn.spacing
                width: Style.spacing.hairline
                height: gridColumn.height - headerRow.height - gridColumn.spacing
                color: root.contentForeground
                opacity: 0.1
              }
            }

            // Month Stepping Controls
            Item {
              width: parent.width
              height: monthNav.height + Style.space(4)

              Item {
                id: monthNav
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: monthLabel.implicitHeight + Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  id: monthLabel
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(140)
                  horizontalAlignment: Text.AlignHCenter
                  text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅁"
                  tooltipText: "Previous month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅂"
                  tooltipText: "Next month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(1)
                }
              }
            }

            // Separator Rule
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(32)
              height: 1
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
            }

            // ==========================================
            // AGENDA / SCHEDULE SECTION
            // ==========================================
            Column {
              width: parent.width - Style.space(32)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)

              // Agenda Header (Refined Design)
              Item {
                width: parent.width
                height: Style.space(28)

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: root.selectedDateKey === root.todayKey ? "󰃭" : "󰸗"
                    color: root.selectedDateKey === root.todayKey ? Color.accent : Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: {
                      if (root.selectedDateKey === root.todayKey) {
                        return "Today · " + Qt.formatDate(root.selectedDate, "dddd, MMM d")
                      }
                      return Qt.formatDate(root.selectedDate, "dddd, MMM d, yyyy")
                    }
                    color: root.selectedDateKey === root.todayKey ? root.contentForeground : Qt.darker(root.contentForeground, 1.2)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  // Count badge pill
                  Rectangle {
                    visible: root.selectedEvents.length > 0
                    width: countText.implicitWidth + Style.space(12)
                    height: Style.space(18)
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      textFormat: Text.PlainText
                      id: countText
                      anchors.centerIn: parent
                      text: String(root.selectedEvents.length)
                      color: root.selectedDateKey === root.todayKey ? Color.accent : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  // Cloud Sync Indicator Tag
                  Rectangle {
                    visible: root.isCloudConnected
                    width: cloudTag.implicitWidth + Style.space(12)
                    height: Style.space(18)
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: Qt.rgba(52/255, 168/255, 83/255, 0.12)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      textFormat: Text.PlainText
                      id: cloudTag
                      anchors.centerIn: parent
                      text: "󰄲 Sync"
                      color: "#34A853"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                // Add Event Toggle Button
                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  PanelActionButton {
                    iconText: root.showAddEvent ? "󰅖" : "󰐕"
                    tooltipText: root.showAddEvent ? "Close Form" : "Create Event"
                    foreground: root.showAddEvent ? Color.accent : root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: root.showAddEvent = !root.showAddEvent
                  }
                }
              }

              // ==========================================
              // IN-PANEL ADD EVENT FORM
              // ==========================================
              Rectangle {
                visible: root.showAddEvent
                width: parent.width
                implicitHeight: newEventCol.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                Column {
                  id: newEventCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(12)
                  spacing: Style.space(10)

                  property string selectedCalId: root.writableCalendars.length > 0 ? root.writableCalendars[0].id : "primary"
                  property string selectedCalName: root.writableCalendars.length > 0 ? root.writableCalendars[0].summary : "Google Calendar"
                  property string selectedColor: root.writableCalendars.length > 0 ? (root.writableCalendars[0].backgroundColor || Color.accent) : Model.PRESET_COLORS[0]
                  property bool addMeetingLink: false
                  property bool isAllDay: false
                  property bool isRecurring: false
                  property string customFreq: "WEEKLY"
                  property int customInterval: 1
                  property var customWeekdays: [Model.weekdayCodeForDate(root.selectedDate)]
                  property string customMonthlyType: "dayOfMonth"
                  property int customMonthDay: root.selectedDate ? root.selectedDate.getDate() : 1
                  property int customNthIndex: root.selectedDate ? (Math.floor((root.selectedDate.getDate() - 1) / 7) + 1) : 1
                  property string customNthWeekday: Model.weekdayCodeForDate(root.selectedDate)
                  property string customEndType: "never"
                  property string customUntilDate: ""
                  property int customCount: 10

                  readonly property string selectedRrule: isRecurring ? Model.buildCustomRrule({
                    freq: customFreq,
                    interval: customInterval,
                    weekdays: customWeekdays,
                    monthlyType: customMonthlyType,
                    monthDay: customMonthDay,
                    nthIndex: customNthIndex,
                    nthWeekday: customNthWeekday,
                    endType: customEndType,
                    untilDate: customUntilDate,
                    count: customCount
                  }) : ""

                  // Form Title Row
                  Item {
                    width: parent.width
                    height: Style.space(24)

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: (root.isCloudConnected ? "NEW GOOGLE CLOUD EVENT · " : "NEW LOCAL EVENT · ") + Qt.formatDate(root.selectedDate, "MMM d, yyyy").toUpperCase()
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      font.letterSpacing: 0.8
                    }

                    PanelActionButton {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰅖"
                      tooltipText: "Cancel"
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: root.showAddEvent = false
                    }
                  }

                  // Event Title Input
                  TextField {
                    id: eventTitleInput
                    width: parent.width
                    placeholderText: "Event title (e.g. Sync Meeting, Dentist)"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                  }

                  // All Day Switch + Time Range Inputs
                  Row {
                    width: parent.width
                    spacing: Style.space(12)

                    Row {
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      ToggleSwitch {
                        id: allDaySwitch
                        checked: newEventCol.isAllDay
                        onToggled: newEventCol.isAllDay = !newEventCol.isAllDay
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "All Day"
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    Row {
                      visible: !newEventCol.isAllDay
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      TextField {
                        id: startTimeInput
                        width: Style.space(80)
                        text: "09:00"
                        placeholderText: "09:00"
                        foreground: root.contentForeground
                        font.family: root.contentFontFamily
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "to"
                        color: Qt.darker(root.contentForeground, 1.8)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      TextField {
                        id: endTimeInput
                        width: Style.space(80)
                        text: "10:00"
                        placeholderText: "10:00"
                        foreground: root.contentForeground
                        font.family: root.contentFontFamily
                      }
                    }
                  }

                  // Location or Meet link input
                  TextField {
                    id: eventLocationInput
                    width: parent.width
                    placeholderText: "Location or Google Meet / Zoom link (Optional)"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                  }

                  // Video Meeting / Google Meet Option
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    ToggleSwitch {
                      id: addMeetingSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: newEventCol.addMeetingLink
                      onToggled: newEventCol.addMeetingLink = !newEventCol.addMeetingLink
                    }

                    Row {
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      Text {
                        textFormat: Text.PlainText
                        text: "󰕧"
                        color: newEventCol.addMeetingLink ? "#34A853" : Qt.darker(root.contentForeground, 1.6)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: root.isCloudConnected ? "Add Google Meet video conferencing" : "Generate meeting link"
                        color: newEventCol.addMeetingLink ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Rectangle {
                        visible: newEventCol.addMeetingLink
                        width: meetTag.implicitWidth + Style.space(10)
                        height: Style.space(18)
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        color: Qt.rgba(52/255, 168/255, 83/255, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                          textFormat: Text.PlainText
                          id: meetTag
                          anchors.centerIn: parent
                          text: "Google Meet"
                          color: "#34A853"
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                    }
                  }

                  // Calendar Destination Selector (When Google Cloud connected)
                  Column {
                    visible: root.isCloudConnected && root.writableCalendars.length > 1
                    width: parent.width
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      text: "SAVE TO CALENDAR:"
                      color: Qt.darker(root.contentForeground, 1.6)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 0.8
                    }

                    Flow {
                      width: parent.width
                      spacing: Style.space(6)

                      Repeater {
                        model: root.writableCalendars

                        Rectangle {
                          id: calChip
                          required property var modelData
                          readonly property bool isSelected: newEventCol.selectedCalId === modelData.id

                          width: chipRow.implicitWidth + Style.space(16)
                          height: Style.space(26)
                          radius: Style.cornerRadius > 0 ? height / 2 : 0

                          color: isSelected
                            ? Style.selectedFillFor(root.contentForeground, Color.accent)
                            : (chipMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))

                          border.width: isSelected ? 1 : 0
                          border.color: isSelected ? Color.accent : "transparent"

                          Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Style.space(6)

                            Rectangle {
                              width: 8
                              height: 8
                              radius: 4
                              color: String(calChip.modelData.backgroundColor || Color.accent)
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                              textFormat: Text.PlainText
                              anchors.verticalCenter: parent.verticalCenter
                              text: String(calChip.modelData.summary || "Calendar")
                              color: calChip.isSelected ? Color.accent : root.contentForeground
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: calChip.isSelected
                            }
                          }

                          MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              newEventCol.selectedCalId = calChip.modelData.id
                              newEventCol.selectedCalName = calChip.modelData.summary
                              newEventCol.selectedColor = calChip.modelData.backgroundColor || Color.accent
                            }
                          }
                        }
                      }
                    }
                  }

                  // Dynamic Recurrence Selector (Clean Toggle + Fully Dynamic Controls)
                  Column {
                    width: parent.width
                    spacing: Style.space(6)

                    // Header Row with Toggle Switch
                    Item {
                      width: parent.width
                      height: Style.space(28)

                      Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)

                        Text {
                          textFormat: Text.PlainText
                          text: "󰑐"
                          color: newEventCol.isRecurring ? Color.accent : Qt.darker(root.contentForeground, 1.6)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: "REPEAT EVENT"
                          color: newEventCol.isRecurring ? root.contentForeground : Qt.darker(root.contentForeground, 1.6)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          font.letterSpacing: 0.8
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }

                      ToggleSwitch {
                        id: repToggle
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: newEventCol.isRecurring
                        onToggled: newEventCol.isRecurring = !newEventCol.isRecurring
                      }
                    }

                    // Dynamic Recurrence Builder Card (Unfolds when isRecurring is true)
                    Rectangle {
                      visible: newEventCol.isRecurring
                      width: parent.width
                      implicitHeight: custCol.implicitHeight + Style.space(20)
                      radius: Style.cornerRadius
                      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                      border.width: 1
                      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

                      Column {
                        id: custCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(12)
                        spacing: Style.space(10)

                        // Section 1: Repeat Every [N] [Days/Weeks/Months/Years]
                        Row {
                          width: parent.width
                          spacing: Style.space(10)

                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Repeat every:"
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }

                          // Stepper: [-] [ 1 ] [+]
                          Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Rectangle {
                              width: Style.space(26)
                              height: Style.space(26)
                              radius: Style.cornerRadius > 0 ? 4 : 0
                              color: decMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                              Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: "−"
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.body
                              }

                              MouseArea {
                                id: decMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                  if (newEventCol.customInterval > 1) newEventCol.customInterval--
                                }
                              }
                            }

                            Rectangle {
                              width: Style.space(32)
                              height: Style.space(26)
                              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                              border.width: 1
                              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                              Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: String(newEventCol.customInterval)
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                              }
                            }

                            Rectangle {
                              width: Style.space(26)
                              height: Style.space(26)
                              radius: Style.cornerRadius > 0 ? 4 : 0
                              color: incMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                              Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: "+"
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.body
                              }

                              MouseArea {
                                id: incMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newEventCol.customInterval++
                              }
                            }
                          }

                          // Unit Selector: [Day] [Week] [Month] [Year]
                          Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(4)

                            Repeater {
                              model: [
                                { label: "Day", freq: "DAILY" },
                                { label: "Week", freq: "WEEKLY" },
                                { label: "Month", freq: "MONTHLY" },
                                { label: "Year", freq: "YEARLY" }
                              ]

                              Rectangle {
                                id: unitBtn
                                required property var modelData
                                readonly property bool isSelected: newEventCol.customFreq === modelData.freq

                                width: uText.implicitWidth + Style.space(12)
                                height: Style.space(26)
                                radius: Style.cornerRadius > 0 ? 4 : 0

                                color: isSelected
                                  ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                  : (uMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))

                                border.width: isSelected ? 1 : 0
                                border.color: isSelected ? Color.accent : "transparent"

                                Text {
                                  textFormat: Text.PlainText
                                  id: uText
                                  anchors.centerIn: parent
                                  text: String(unitBtn.modelData.label) + (newEventCol.customInterval > 1 ? "s" : "")
                                  color: unitBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: unitBtn.isSelected
                                }

                                MouseArea {
                                  id: uMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: newEventCol.customFreq = unitBtn.modelData.freq
                                }
                              }
                            }
                          }
                        }

                        // Section 2: Weekly Days Multi-Select (When freq === "WEEKLY")
                        Column {
                          visible: newEventCol.customFreq === "WEEKLY"
                          width: parent.width
                          spacing: Style.space(4)

                          Text {
                            textFormat: Text.PlainText
                            text: "Repeat on days:"
                            color: Qt.darker(root.contentForeground, 1.6)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Row {
                            spacing: Style.space(6)

                            Repeater {
                              model: [
                                { label: "S", code: "SU", name: "Sun" },
                                { label: "M", code: "MO", name: "Mon" },
                                { label: "T", code: "TU", name: "Tue" },
                                { label: "W", code: "WE", name: "Wed" },
                                { label: "T", code: "TH", name: "Thu" },
                                { label: "F", code: "FR", name: "Fri" },
                                { label: "S", code: "SA", name: "Sat" }
                              ]

                              Rectangle {
                                id: dayBubble
                                required property var modelData
                                readonly property bool isSelected: newEventCol.customWeekdays.indexOf(modelData.code) !== -1

                                width: Style.space(30)
                                height: Style.space(30)
                                radius: width / 2

                                color: isSelected
                                  ? Color.accent
                                  : (dayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08))

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.centerIn: parent
                                  text: String(dayBubble.modelData.label)
                                  color: dayBubble.isSelected ? "#ffffff" : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: true
                                }

                                MouseArea {
                                  id: dayMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: {
                                    var list = newEventCol.customWeekdays.slice()
                                    var idx = list.indexOf(dayBubble.modelData.code)
                                    if (idx !== -1) {
                                      if (list.length > 1) list.splice(idx, 1)
                                    } else {
                                      list.push(dayBubble.modelData.code)
                                    }
                                    newEventCol.customWeekdays = list
                                  }
                                }

                                PanelToolTip {
                                  visible: dayMouse.containsMouse
                                  text: String(dayBubble.modelData.name)
                                  fontFamily: root.contentFontFamily
                                }
                              }
                            }
                          }
                        }

                        // Section 3: Monthly Options (Fully Dynamic Interactive Pickers)
                        Column {
                          visible: newEventCol.customFreq === "MONTHLY"
                          width: parent.width
                          spacing: Style.space(8)

                          // Mode Selector Tabs: [ On Day of Month ] [ On Nth Weekday ]
                          Row {
                            spacing: Style.space(8)

                            Rectangle {
                              id: mDayModeBtn
                              readonly property bool isSelected: newEventCol.customMonthlyType === "dayOfMonth"
                              width: mDayModeText.implicitWidth + Style.space(16)
                              height: Style.space(26)
                              radius: Style.cornerRadius > 0 ? 4 : 0
                              color: isSelected
                                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                : (mDayModeMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                              border.width: isSelected ? 1 : 0
                              border.color: isSelected ? Color.accent : "transparent"

                              Row {
                                id: mDayModeText
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                  textFormat: Text.PlainText
                                  text: "󰃭"
                                  color: mDayModeBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                  textFormat: Text.PlainText
                                  text: "On Day of Month"
                                  color: mDayModeBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: mDayModeBtn.isSelected
                                  anchors.verticalCenter: parent.verticalCenter
                                }
                              }

                              MouseArea {
                                id: mDayModeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newEventCol.customMonthlyType = "dayOfMonth"
                              }
                            }

                            Rectangle {
                              id: mNthModeBtn
                              readonly property bool isSelected: newEventCol.customMonthlyType === "nthWeekday"
                              width: mNthModeText.implicitWidth + Style.space(16)
                              height: Style.space(26)
                              radius: Style.cornerRadius > 0 ? 4 : 0
                              color: isSelected
                                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                : (mNthModeMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                              border.width: isSelected ? 1 : 0
                              border.color: isSelected ? Color.accent : "transparent"

                              Row {
                                id: mNthModeText
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                  textFormat: Text.PlainText
                                  text: "󰃮"
                                  color: mNthModeBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                  textFormat: Text.PlainText
                                  text: "On Nth Weekday"
                                  color: mNthModeBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: mNthModeBtn.isSelected
                                  anchors.verticalCenter: parent.verticalCenter
                                }
                              }

                              MouseArea {
                                id: mNthModeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newEventCol.customMonthlyType = "nthWeekday"
                              }
                            }
                          }

                          // Mode 1 Controls: Dynamic Day Stepper & Quick Day Chips (1 - 31)
                          Row {
                            visible: newEventCol.customMonthlyType === "dayOfMonth"
                            width: parent.width
                            spacing: Style.space(10)

                            Text {
                              textFormat: Text.PlainText
                              anchors.verticalCenter: parent.verticalCenter
                              text: "Day of month:"
                              color: Qt.darker(root.contentForeground, 1.4)
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                            }

                            // Stepper: [-] [ 25 ] [+]
                            Row {
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: 2

                              Rectangle {
                                width: Style.space(26)
                                height: Style.space(26)
                                radius: Style.cornerRadius > 0 ? 4 : 0
                                color: mDecMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.centerIn: parent
                                  text: "−"
                                  color: root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.body
                                }

                                MouseArea {
                                  id: mDecMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: {
                                    if (newEventCol.customMonthDay > 1) newEventCol.customMonthDay--
                                    else newEventCol.customMonthDay = 31
                                  }
                                }
                              }

                              Rectangle {
                                width: Style.space(36)
                                height: Style.space(26)
                                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.centerIn: parent
                                  text: String(newEventCol.customMonthDay)
                                  color: root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: true
                                }
                              }

                              Rectangle {
                                width: Style.space(26)
                                height: Style.space(26)
                                radius: Style.cornerRadius > 0 ? 4 : 0
                                color: mIncMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.centerIn: parent
                                  text: "+"
                                  color: root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.body
                                }

                                MouseArea {
                                  id: mIncMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: {
                                    if (newEventCol.customMonthDay < 31) newEventCol.customMonthDay++
                                    else newEventCol.customMonthDay = 1
                                  }
                                }
                              }
                            }

                            // Quick Day Chips
                            Row {
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: 4

                              Repeater {
                                model: [1, 5, 10, 15, 20, 25, 30, 31]

                                Rectangle {
                                  id: qDayChip
                                  required property int modelData
                                  readonly property bool isSelected: newEventCol.customMonthDay === modelData
                                  width: qDayText.implicitWidth + Style.space(8)
                                  height: Style.space(24)
                                  radius: Style.cornerRadius > 0 ? 4 : 0
                                  color: isSelected ? Style.selectedFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                                  border.width: isSelected ? 1 : 0
                                  border.color: isSelected ? Color.accent : "transparent"

                                  Text {
                                    textFormat: Text.PlainText
                                    id: qDayText
                                    anchors.centerIn: parent
                                    text: String(qDayChip.modelData)
                                    color: qDayChip.isSelected ? Color.accent : root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: qDayChip.isSelected
                                  }

                                  MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: newEventCol.customMonthDay = qDayChip.modelData
                                  }
                                }
                              }
                            }
                          }

                          // Mode 2 Controls: Dynamic Nth Position & Weekday Pickers
                          Column {
                            visible: newEventCol.customMonthlyType === "nthWeekday"
                            width: parent.width
                            spacing: Style.space(6)

                            // Row A: Position (1st, 2nd, 3rd, 4th, Last)
                            Row {
                              spacing: Style.space(6)

                              Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "The"
                                color: Qt.darker(root.contentForeground, 1.4)
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                              }

                              Repeater {
                                model: [
                                  { label: "1st", idx: 1 },
                                  { label: "2nd", idx: 2 },
                                  { label: "3rd", idx: 3 },
                                  { label: "4th", idx: 4 },
                                  { label: "Last", idx: -1 }
                                ]

                                Rectangle {
                                  id: nthPosChip
                                  required property var modelData
                                  readonly property bool isSelected: newEventCol.customNthIndex === modelData.idx

                                  width: nthPosText.implicitWidth + Style.space(12)
                                  height: Style.space(26)
                                  radius: Style.cornerRadius > 0 ? 4 : 0

                                  color: isSelected
                                    ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                    : (nthPosMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))

                                  border.width: isSelected ? 1 : 0
                                  border.color: isSelected ? Color.accent : "transparent"

                                  Text {
                                    textFormat: Text.PlainText
                                    id: nthPosText
                                    anchors.centerIn: parent
                                    text: String(nthPosChip.modelData.label)
                                    color: nthPosChip.isSelected ? Color.accent : root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: nthPosChip.isSelected
                                  }

                                  MouseArea {
                                    id: nthPosMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: newEventCol.customNthIndex = nthPosChip.modelData.idx
                                  }
                                }
                              }
                            }

                            // Row B: Weekday (Sun, Mon, Tue, Wed, Thu, Fri, Sat)
                            Row {
                              spacing: Style.space(6)

                              Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "on"
                                color: Qt.darker(root.contentForeground, 1.4)
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                              }

                              Repeater {
                                model: [
                                  { label: "Sun", code: "SU" },
                                  { label: "Mon", code: "MO" },
                                  { label: "Tue", code: "TU" },
                                  { label: "Wed", code: "WE" },
                                  { label: "Thu", code: "TH" },
                                  { label: "Fri", code: "FR" },
                                  { label: "Sat", code: "SA" }
                                ]

                                Rectangle {
                                  id: nthDayChip
                                  required property var modelData
                                  readonly property bool isSelected: newEventCol.customNthWeekday === modelData.code

                                  width: nthDayText.implicitWidth + Style.space(12)
                                  height: Style.space(26)
                                  radius: Style.cornerRadius > 0 ? 4 : 0

                                  color: isSelected
                                    ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                    : (nthDayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))

                                  border.width: isSelected ? 1 : 0
                                  border.color: isSelected ? Color.accent : "transparent"

                                  Text {
                                    textFormat: Text.PlainText
                                    id: nthDayText
                                    anchors.centerIn: parent
                                    text: String(nthDayChip.modelData.label)
                                    color: nthDayChip.isSelected ? Color.accent : root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: nthDayChip.isSelected
                                  }

                                  MouseArea {
                                    id: nthDayMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: newEventCol.customNthWeekday = nthDayChip.modelData.code
                                  }
                                }
                              }
                            }
                          }
                        }

                        // Section 4: Ends (Fully Configurable Times or End Date)
                        Column {
                          width: parent.width
                          spacing: Style.space(6)

                          Text {
                            textFormat: Text.PlainText
                            text: "Ends:"
                            color: Qt.darker(root.contentForeground, 1.4)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)

                            // Option 1: Never
                            Rectangle {
                              id: endNeverBtn
                              readonly property bool isSelected: newEventCol.customEndType === "never"
                              anchors.verticalCenter: parent.verticalCenter
                              width: endNevText.implicitWidth + Style.space(16)
                              height: Style.space(26)
                              radius: Style.cornerRadius > 0 ? 4 : 0
                              color: isSelected
                                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                : (endNevMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                              border.width: isSelected ? 1 : 0
                              border.color: isSelected ? Color.accent : "transparent"

                              Text {
                                textFormat: Text.PlainText
                                id: endNevText
                                anchors.centerIn: parent
                                text: "Never"
                                color: endNeverBtn.isSelected ? Color.accent : root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: endNeverBtn.isSelected
                              }

                              MouseArea {
                                id: endNevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newEventCol.customEndType = "never"
                              }
                            }

                            // Option 2: After N times (Mode Button + Separate Stepper Controls)
                            Row {
                              spacing: Style.space(6)
                              anchors.verticalCenter: parent.verticalCenter

                              Rectangle {
                                id: endCountBtn
                                readonly property bool isSelected: newEventCol.customEndType === "count"
                                width: endCntText.implicitWidth + Style.space(16)
                                height: Style.space(26)
                                radius: Style.cornerRadius > 0 ? 4 : 0
                                color: isSelected
                                  ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                  : (endCntMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                                border.width: isSelected ? 1 : 0
                                border.color: isSelected ? Color.accent : "transparent"

                                Text {
                                  textFormat: Text.PlainText
                                  id: endCntText
                                  anchors.centerIn: parent
                                  text: "After"
                                  color: endCountBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: endCountBtn.isSelected
                                }

                                MouseArea {
                                  id: endCntMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: newEventCol.customEndType = "count"
                                }
                              }

                              // Count Stepper: [-] [ 10 ] [+] times
                              Row {
                                visible: newEventCol.customEndType === "count"
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Rectangle {
                                  width: Style.space(24)
                                  height: Style.space(24)
                                  radius: Style.cornerRadius > 0 ? 3 : 0
                                  color: cDecMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                                  Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.body
                                  }

                                  MouseArea {
                                    id: cDecMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                      if (newEventCol.customCount > 1) newEventCol.customCount--
                                    }
                                  }
                                }

                                Rectangle {
                                  width: Style.space(34)
                                  height: Style.space(24)
                                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                                  border.width: 1
                                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                                  Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: String(newEventCol.customCount)
                                    color: Color.accent
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }
                                }

                                Rectangle {
                                  width: Style.space(24)
                                  height: Style.space(24)
                                  radius: Style.cornerRadius > 0 ? 3 : 0
                                  color: cIncMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                                  Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.body
                                  }

                                  MouseArea {
                                    id: cIncMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: newEventCol.customCount++
                                  }
                                }

                                Text {
                                  textFormat: Text.PlainText
                                  anchors.verticalCenter: parent.verticalCenter
                                  text: "times"
                                  color: Qt.darker(root.contentForeground, 1.4)
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            // Option 3: On Date (Mode Button + Separate Input Box)
                            Row {
                              spacing: Style.space(6)
                              anchors.verticalCenter: parent.verticalCenter

                              Rectangle {
                                id: endUntilBtn
                                readonly property bool isSelected: newEventCol.customEndType === "until"
                                width: endUntilText.implicitWidth + Style.space(16)
                                height: Style.space(26)
                                radius: Style.cornerRadius > 0 ? 4 : 0
                                color: isSelected
                                  ? Style.selectedFillFor(root.contentForeground, Color.accent)
                                  : (endUntilMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                                border.width: isSelected ? 1 : 0
                                border.color: isSelected ? Color.accent : "transparent"

                                Text {
                                  textFormat: Text.PlainText
                                  id: endUntilText
                                  anchors.centerIn: parent
                                  text: "On date"
                                  color: endUntilBtn.isSelected ? Color.accent : root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: endUntilBtn.isSelected
                                }

                                MouseArea {
                                  id: endUntilMouse
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onClicked: {
                                    newEventCol.customEndType = "until"
                                    if (!newEventCol.customUntilDate) {
                                      newEventCol.customUntilDate = root.selectedDate.getFullYear() + "-12-31"
                                    }
                                  }
                                }
                              }

                              // Date Input Field
                              Rectangle {
                                visible: newEventCol.customEndType === "until"
                                width: Style.space(96)
                                height: Style.space(24)
                                radius: 3
                                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                                border.width: 1
                                border.color: untilDateInput.activeFocus ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)
                                anchors.verticalCenter: parent.verticalCenter

                                TextInput {
                                  id: untilDateInput
                                  anchors.fill: parent
                                  anchors.leftMargin: 6
                                  anchors.rightMargin: 6
                                  verticalAlignment: TextInput.AlignVCenter
                                  text: newEventCol.customUntilDate || (root.selectedDate.getFullYear() + "-12-31")
                                  color: root.contentForeground
                                  font.family: root.contentFontFamily
                                  font.pixelSize: Style.font.caption
                                  selectByMouse: true
                                  onTextEdited: {
                                    newEventCol.customUntilDate = text
                                    newEventCol.customEndType = "until"
                                  }
                                }
                              }
                            }
                          }
                        }

                        // Live Rule Summary
                        Rectangle {
                          width: parent.width
                          implicitHeight: summRow.implicitHeight + Style.space(10)
                          radius: Style.cornerRadius > 0 ? 4 : 0
                          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

                          Row {
                            id: summRow
                            anchors.centerIn: parent
                            spacing: Style.space(6)
                            width: parent.width - Style.space(16)

                            Text {
                              textFormat: Text.PlainText
                              text: "󰑐"
                              color: Color.accent
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                              textFormat: Text.PlainText
                              text: Model.describeRrule(newEventCol.selectedRrule)
                              color: root.contentForeground
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                              elide: Text.ElideRight
                              width: parent.width - Style.space(20)
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }
                        }
                      }
                    }
                  }
                  // Color Picker + Save Button Row
                  Item {
                    width: parent.width
                    height: createBtn.implicitHeight

                    Row {
                      visible: !root.isCloudConnected
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Repeater {
                        model: Model.PRESET_COLORS

                        Rectangle {
                          required property var modelData
                          width: 20
                          height: 20
                          radius: 10
                          color: String(modelData)
                          border.width: newEventCol.selectedColor === modelData ? 2 : 0
                          border.color: root.contentForeground

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: newEventCol.selectedColor = String(parent.modelData)
                          }
                        }
                      }
                    }

                    Row {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Button {
                        text: "Cancel"
                        foreground: root.contentForeground
                        onClicked: root.showAddEvent = false
                      }

                      Button {
                        id: createBtn
                        text: root.isCloudConnected ? "Save to Google Cloud" : "Save Event"
                        iconText: "󰐕"
                        foreground: root.contentForeground
                        accent: Color.accent
                        onClicked: {
                          if (eventTitleInput.text.trim()) {
                            root.addEvent(
                              eventTitleInput.text,
                              root.selectedDateKey,
                              newEventCol.isAllDay,
                              startTimeInput.text,
                              endTimeInput.text,
                              newEventCol.selectedColor,
                              newEventCol.selectedCalName,
                              eventLocationInput.text,
                              "",
                              newEventCol.selectedCalId,
                              newEventCol.selectedRrule,
                              newEventCol.addMeetingLink
                            )
                            eventTitleInput.text = ""
                            eventLocationInput.text = ""
                            newEventCol.addMeetingLink = false
                            newEventCol.selectedRepeatIdx = 0
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Event List
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.selectedEvents.length > 0

                Repeater {
                  model: root.selectedEvents

                  Rectangle {
                    id: eventCard
                    required property var modelData

                    readonly property bool isPast: {
                      var ev = eventCard.modelData
                      if (!ev) return false
                      if (ev.dateKey < root.todayKey) return true
                      if (ev.dateKey > root.todayKey) return false
                      if (ev.allDay) return false

                      var curMin = root.currentMinutes
                      var startParts = (ev.startTime || "00:00").split(":")
                      var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)
                      var endMin = startMin + 30
                      if (ev.endTime) {
                        var endParts = ev.endTime.split(":")
                        var calcEnd = parseInt(endParts[0], 10) * 60 + parseInt(endParts[1] || "0", 10)
                        if (calcEnd > startMin) endMin = calcEnd
                      }
                      return endMin <= curMin
                    }

                    readonly property bool isOngoing: {
                      var ev = eventCard.modelData
                      if (!ev) return false
                      if (ev.dateKey !== root.todayKey || ev.allDay) return false

                      var curMin = root.currentMinutes
                      var startParts = (ev.startTime || "00:00").split(":")
                      var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)
                      var endMin = startMin + 30
                      if (ev.endTime) {
                        var endParts = ev.endTime.split(":")
                        var calcEnd = parseInt(endParts[0], 10) * 60 + parseInt(endParts[1] || "0", 10)
                        if (calcEnd > startMin) endMin = calcEnd
                      }
                      return startMin <= curMin && curMin < endMin
                    }

                    width: parent.width
                    implicitHeight: cardContent.implicitHeight + Style.space(16)
                    radius: Style.cornerRadius
                    opacity: isPast ? 0.65 : 1.0
                    color: cardMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                    // Calendar Color Accent Bar on Left
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: 4
                      radius: 2
                      color: String(eventCard.modelData.calendarColor || Color.accent)
                      opacity: eventCard.isPast ? 0.5 : 1.0
                    }

                    MouseArea {
                      id: cardMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: eventCard.modelData.meetUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: {
                        if (eventCard.modelData.meetUrl) root.openMeetLink(eventCard.modelData.meetUrl)
                      }
                    }

                    Column {
                      id: cardContent
                      anchors.left: parent.left
                      anchors.right: actionRow.left
                      anchors.leftMargin: Style.space(14)
                      anchors.rightMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(3)

                      // Time + Status Badge + Calendar Tag Row
                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(eventCard.modelData.timeDisplay || "All day")
                          color: eventCard.isPast ? Qt.darker(root.contentForeground, 1.8) : (eventCard.modelData.allDay ? Qt.darker(root.contentForeground, 1.4) : Color.accent)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: !eventCard.isPast
                        }



                        // Ongoing Badge
                        Rectangle {
                          visible: eventCard.isOngoing
                          anchors.verticalCenter: parent.verticalCenter
                          width: onRow.implicitWidth + Style.space(8)
                          height: Style.space(16)
                          radius: Style.cornerRadius > 0 ? height / 2 : 0
                          color: Qt.rgba(52/255, 168/255, 83/255, 0.15)

                          Row {
                            id: onRow
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                              textFormat: Text.PlainText
                              text: "󰐊"
                              color: "#34A853"
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                            }
                            Text {
                              textFormat: Text.PlainText
                              text: "Ongoing"
                              color: "#34A853"
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }
                        }

                        Text {
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: "• " + String(eventCard.modelData.calendarName || "Event")
                          color: Qt.darker(root.contentForeground, 1.8)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      // Event Title (Strikethrough and dimmed if past/completed)
                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: String(eventCard.modelData.summary || "Untitled Event")
                        color: eventCard.isPast ? Qt.darker(root.contentForeground, 1.6) : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: !eventCard.isPast
                        font.strikeout: eventCard.isPast
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }

                      // Location or Meet link (if available)
                      Row {
                        width: parent.width
                        spacing: Style.space(8)
                        visible: eventCard.modelData.location !== "" || eventCard.modelData.meetUrl !== ""

                        Row {
                          spacing: 4
                          visible: eventCard.modelData.meetUrl !== ""

                          Text {
                            textFormat: Text.PlainText
                            text: "󰕧"
                            color: "#34A853"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: "Google Meet"
                            color: "#34A853"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Row {
                          spacing: 4
                          visible: eventCard.modelData.location !== "" && eventCard.modelData.meetUrl === ""

                          Text {
                            textFormat: Text.PlainText
                            text: "󰍎"
                            color: Qt.darker(root.contentForeground, 1.6)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: String(eventCard.modelData.location)
                            color: Qt.darker(root.contentForeground, 1.6)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, Style.space(260))
                          }
                        }
                      }
                    }

                    // Actions Row (Join Meeting + Delete)
                    Row {
                      id: actionRow
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      // Dedicated Join Meeting Button
                      Rectangle {
                        visible: eventCard.modelData.meetUrl !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: joinRow.implicitWidth + Style.space(16)
                        height: Style.space(26)
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        color: joinMouse.containsMouse ? "#2d8e47" : "#34A853"

                        Row {
                          id: joinRow
                          anchors.centerIn: parent
                          spacing: Style.space(4)

                          Text {
                            textFormat: Text.PlainText
                            text: "󰕧"
                            color: "#ffffff"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            textFormat: Text.PlainText
                            text: "Join"
                            color: "#ffffff"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        MouseArea {
                          id: joinMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openMeetLink(eventCard.modelData.meetUrl)
                        }

                        PanelToolTip {
                          visible: joinMouse.containsMouse
                          text: "Join Meeting in Browser"
                          fontFamily: root.contentFontFamily
                        }
                      }

                      // Delete button for local and cloud events
                      PanelActionButton {
                        id: delEventBtn
                        visible: !!eventCard.modelData.isLocal || (!!eventCard.modelData.isCloud && root.isCloudConnected)
                        iconText: "󰆴"
                        tooltipText: "Delete Event"
                        foreground: Qt.darker(root.contentForeground, 1.8)
                        hoverColor: Color.urgent || "#EA4335"
                        fontFamily: root.contentFontFamily
                        onClicked: root.requestDeleteEvent(eventCard.modelData)
                      }
                    }
                  }
                }
              }

              // Empty State
              Rectangle {
                visible: root.selectedEvents.length === 0 && !root.showAddEvent
                width: parent.width
                implicitHeight: Style.space(80)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.03)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.hidePastEvents && root.selectedDateKey === root.todayKey && (root.eventsByDate[root.todayKey] || []).length > 0)
                      ? "All scheduled events for today are completed"
                      : (root.calendars.length === 0 && root.localEvents.length === 0 && !root.isCloudConnected ? "No events scheduled" : "No events scheduled for this day")
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: "Click + to create an event directly here"
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              // ==========================================
              // TOMORROW'S SCHEDULE SECTION (OPTIONAL)
              // ==========================================
              Column {
                visible: root.selectedDateKey === root.todayKey && root.showTomorrowEvents && root.tomorrowEvents.length > 0
                width: parent.width
                spacing: Style.space(8)

                // Divider Separator
                Item {
                  width: parent.width
                  height: Style.space(16)

                  Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 1
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  }
                }

                // Tomorrow Header (Exact match with Today header style)
                Item {
                  width: parent.width
                  height: Style.space(28)

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: "󰃮"
                      color: Qt.darker(root.contentForeground, 1.4)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Tomorrow · " + Qt.formatDate(root.tomorrowDate, "dddd, MMM d")
                      color: Qt.darker(root.contentForeground, 1.2)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    // Count badge pill
                    Rectangle {
                      visible: root.tomorrowEvents.length > 0
                      width: tomCountText.implicitWidth + Style.space(12)
                      height: Style.space(18)
                      radius: Style.cornerRadius > 0 ? height / 2 : 0
                      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                      border.width: 1
                      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        textFormat: Text.PlainText
                        id: tomCountText
                        anchors.centerIn: parent
                        text: String(root.tomorrowEvents.length)
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }

                Repeater {
                  model: root.tomorrowEvents

                  Rectangle {
                    id: tomEventCard
                    required property var modelData
                    width: parent.width
                    implicitHeight: tomCardContent.implicitHeight + Style.space(16)
                    radius: Style.cornerRadius
                    color: tomCardMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: 4
                      radius: 2
                      color: String(tomEventCard.modelData.calendarColor || Color.accent)
                    }

                    MouseArea {
                      id: tomCardMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: tomEventCard.modelData.meetUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: {
                        if (tomEventCard.modelData.meetUrl) root.openMeetLink(tomEventCard.modelData.meetUrl)
                      }
                    }

                    Column {
                      id: tomCardContent
                      anchors.left: parent.left
                      anchors.right: tomActionRow.left
                      anchors.leftMargin: Style.space(14)
                      anchors.rightMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(3)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(tomEventCard.modelData.timeDisplay || "All day")
                          color: tomEventCard.modelData.allDay ? Qt.darker(root.contentForeground, 1.4) : Color.accent
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        Text {
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: "• " + String(tomEventCard.modelData.calendarName || "Event")
                          color: Qt.darker(root.contentForeground, 1.8)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: String(tomEventCard.modelData.summary || "Untitled Event")
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }

                      Row {
                        width: parent.width
                        spacing: Style.space(8)
                        visible: tomEventCard.modelData.location !== "" || tomEventCard.modelData.meetUrl !== ""

                        Row {
                          spacing: 4
                          visible: tomEventCard.modelData.meetUrl !== ""

                          Text {
                            textFormat: Text.PlainText
                            text: "󰕧"
                            color: "#34A853"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: "Google Meet"
                            color: "#34A853"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Row {
                          spacing: 4
                          visible: tomEventCard.modelData.location !== "" && tomEventCard.modelData.meetUrl === ""

                          Text {
                            textFormat: Text.PlainText
                            text: "󰍎"
                            color: Qt.darker(root.contentForeground, 1.6)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Text {
                            textFormat: Text.PlainText
                            text: String(tomEventCard.modelData.location)
                            color: Qt.darker(root.contentForeground, 1.6)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, Style.space(260))
                          }
                        }
                      }
                    }

                    // Tomorrow Actions Row
                    Row {
                      id: tomActionRow
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      Rectangle {
                        visible: tomEventCard.modelData.meetUrl !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: tomJoinRow.implicitWidth + Style.space(16)
                        height: Style.space(26)
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        color: tomJoinMouse.containsMouse ? "#2d8e47" : "#34A853"

                        Row {
                          id: tomJoinRow
                          anchors.centerIn: parent
                          spacing: Style.space(4)

                          Text {
                            textFormat: Text.PlainText
                            text: "󰕧"
                            color: "#ffffff"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            textFormat: Text.PlainText
                            text: "Join"
                            color: "#ffffff"
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        MouseArea {
                          id: tomJoinMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openMeetLink(tomEventCard.modelData.meetUrl)
                        }

                        PanelToolTip {
                          visible: tomJoinMouse.containsMouse
                          text: "Join Meeting in Browser"
                          fontFamily: root.contentFontFamily
                        }
                      }

                      PanelActionButton {
                        id: tomDelBtn
                        visible: !!tomEventCard.modelData.isLocal || (!!tomEventCard.modelData.isCloud && root.isCloudConnected)
                        iconText: "󰆴"
                        tooltipText: "Delete Event"
                        foreground: Qt.darker(root.contentForeground, 1.8)
                        hoverColor: Color.urgent || "#EA4335"
                        fontFamily: root.contentFontFamily
                        onClicked: root.requestDeleteEvent(tomEventCard.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          // ==========================================
          // VIEW 2: GOOGLE CALENDAR SETTINGS & FEEDS
          // ==========================================
          Column {
            visible: root.showSettings
            width: parent.width - Style.space(32)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(14)

            // Header Row
            Item {
              width: parent.width
              height: Style.space(28)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                PanelActionButton {
                  iconText: "󰅁"
                  tooltipText: "Back to Calendar"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.showSettings = false
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "GOOGLE CALENDAR SETTINGS"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  font.letterSpacing: 1
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.syncStatusText
                color: Qt.darker(root.contentForeground, 1.8)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // ==========================================
            // CARD 0: DISPLAY OPTIONS
            // ==========================================
            Rectangle {
              width: parent.width
              implicitHeight: barOptCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

              Column {
                id: barOptCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(12)

                Text {
                  textFormat: Text.PlainText
                  text: "DISPLAY & AGENDA OPTIONS"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  font.letterSpacing: 0.8
                }

                // 1. Show Next Event in Top Bar
                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - nextEvSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Show Next Event in Top Bar"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Displays your upcoming event title and time countdown next to the clock on the top bar"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: nextEvSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("showNextEvent", false) === true
                    onToggled: root.persistSettings({ showNextEvent: !root.setting("showNextEvent", false) })
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                }

                // 2. Show Only Upcoming Events in Agenda
                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - hidePastSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Show Only Upcoming Events in Agenda"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Hides completed/past events from today's agenda schedule view"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: hidePastSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("hidePastEvents", false) === true
                    onToggled: root.persistSettings({ hidePastEvents: !root.setting("hidePastEvents", false) })
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                }

                // 3. Show Tomorrow Events
                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - showTomSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Show Tomorrow's Events in Agenda"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Appends tomorrow's schedule below today's agenda (and looks ahead on top bar when today is finished)"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: showTomSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("showTomorrowEvents", false) === true
                    onToggled: root.persistSettings({ showTomorrowEvents: !root.setting("showTomorrowEvents", false) })
                  }
                }
              }
            }

            // ==========================================
            // CARD 0.5: EVENT NOTIFICATIONS
            // ==========================================
            Rectangle {
              width: parent.width
              implicitHeight: notifOptCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

              Column {
                id: notifOptCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(12)

                Item {
                  width: parent.width
                  height: testNotifBtn.implicitHeight

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "EVENT NOTIFICATIONS"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    font.letterSpacing: 0.8
                  }

                  Button {
                    id: testNotifBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Send Test"
                    iconText: "󰂚"
                    foreground: root.contentForeground
                    accent: Color.accent
                    onClicked: root.sendTestNotification()
                  }
                }

                // 1. Enable Notifications Switch
                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - notifEnSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Desktop Reminders"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Send desktop notifications for upcoming events and meetings with 1-click Join button"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: notifEnSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("enableNotifications", true) === true
                    onToggled: root.persistSettings({ enableNotifications: !root.setting("enableNotifications", true) })
                  }
                }

                // 2. Notification Timing Chips
                Column {
                  visible: root.setting("enableNotifications", true) === true
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: "REMIND ME IN ADVANCE:"
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                  }

                  Row {
                    spacing: Style.space(6)
                    Repeater {
                      model: [
                        { label: "5 min", val: 5 },
                        { label: "10 min", val: 10 },
                        { label: "15 min", val: 15 },
                        { label: "30 min", val: 30 }
                      ]

                      Rectangle {
                        id: timeChip
                        required property var modelData
                        readonly property bool isSelected: (parseInt(root.setting("notificationMinutes", 10), 10) || 10) === modelData.val
                        width: timeChipText.implicitWidth + Style.space(16)
                        height: Style.space(26)
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        color: isSelected
                          ? Style.selectedFillFor(root.contentForeground, Color.accent)
                          : (tChipMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                        border.width: isSelected ? 1 : 0
                        border.color: isSelected ? Color.accent : "transparent"

                        Text {
                          textFormat: Text.PlainText
                          id: timeChipText
                          anchors.centerIn: parent
                          text: timeChip.modelData.label
                          color: timeChip.isSelected ? Color.accent : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: timeChip.isSelected
                        }

                        MouseArea {
                          id: tChipMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.persistSettings({ notificationMinutes: timeChip.modelData.val })
                        }
                      }
                    }
                  }
                }

                // 3. Notify at Event Start Time
                Row {
                  visible: root.setting("enableNotifications", true) === true
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - notifStartSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Notify at Start Time"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Send an additional notification at the exact start time of the event"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: notifStartSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("notifyAtStart", true) === true
                    onToggled: root.persistSettings({ notifyAtStart: !root.setting("notifyAtStart", true) })
                  }
                }

                // 4. Stay on Screen Until Clicked (Persistent Reminders)
                Row {
                  visible: root.setting("enableNotifications", true) === true
                  width: parent.width
                  spacing: Style.space(10)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - notifPersistSw.width - Style.space(12)
                    spacing: 2

                    Text {
                      textFormat: Text.PlainText
                      text: "Stay on Screen Until Clicked"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "Keep reminders visible indefinitely until you click to join or dismiss"
                      color: Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }

                  ToggleSwitch {
                    id: notifPersistSw
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.setting("persistentNotifications", true) === true
                    onToggled: root.persistSettings({ persistentNotifications: !root.setting("persistentNotifications", true) })
                  }
                }
              }
            }

            // ==========================================
            // CARD 1: GOOGLE CLOUD OAUTH 2.0 (TWO-WAY SYNC)
            // ==========================================
            Rectangle {
              width: parent.width
              implicitHeight: oauthCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
              border.width: 1
              border.color: root.isCloudConnected ? Qt.rgba(52/255, 168/255, 83/255, 0.4) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

              Column {
                id: oauthCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(10)

                // Header
                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GOOGLE CLOUD TWO-WAY SYNC (OAUTH 2.0)"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    font.letterSpacing: 0.8
                  }

                  Rectangle {
                    width: statusBadge.implicitWidth + Style.space(10)
                    height: Style.space(18)
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: root.isCloudConnected ? Qt.rgba(52/255, 168/255, 83/255, 0.2) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      textFormat: Text.PlainText
                      id: statusBadge
                      anchors.centerIn: parent
                      text: root.isCloudConnected ? "Connected" : (root.hasClientCredentials ? "Ready to Connect" : "Setup Required")
                      color: root.isCloudConnected ? "#34A853" : Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.isCloudConnected
                    ? "Your Google Calendar account is connected. Any events you create or delete in the clock will sync directly with Google Cloud servers and your other devices."
                    : "Connect with Google OAuth 2.0 to create, edit, and delete events directly on Google Cloud Calendar from your desktop."
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                // Connected Actions
                Row {
                  visible: root.isCloudConnected
                  width: parent.width
                  spacing: Style.space(8)

                  Button {
                    text: "Sync Cloud Now"
                    iconText: "󰑐"
                    foreground: root.contentForeground
                    accent: Color.accent
                    onClicked: root.syncAllCalendars()
                  }

                  Button {
                    text: "Disconnect Account"
                    iconText: "󰆴"
                    foreground: root.contentForeground
                    onClicked: root.logoutGoogle()
                  }
                }

                // Auto-Sync Frequency Chips
                Column {
                  visible: root.isCloudConnected
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: "BACKGROUND AUTO-SYNC INTERVAL:"
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                  }

                  Row {
                    spacing: Style.space(6)
                    Repeater {
                      model: [
                        { label: "1 min", val: 1 },
                        { label: "2 min", val: 2 },
                        { label: "5 min", val: 5 },
                        { label: "15 min", val: 15 }
                      ]

                      Rectangle {
                        id: syncChip
                        required property var modelData
                        readonly property bool isSelected: (parseInt(root.setting("syncIntervalMinutes", 2), 10) || 2) === modelData.val
                        width: syncChipText.implicitWidth + Style.space(16)
                        height: Style.space(26)
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        color: isSelected
                          ? Style.selectedFillFor(root.contentForeground, Color.accent)
                          : (sChipMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05))
                        border.width: isSelected ? 1 : 0
                        border.color: isSelected ? Color.accent : "transparent"

                        Text {
                          textFormat: Text.PlainText
                          id: syncChipText
                          anchors.centerIn: parent
                          text: syncChip.modelData.label
                          color: syncChip.isSelected ? Color.accent : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: syncChip.isSelected
                        }

                        MouseArea {
                          id: sChipMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.persistSettings({ syncIntervalMinutes: syncChip.modelData.val })
                        }
                      }
                    }
                  }
                }

                // Cloud Calendars Visibility & Filter List
                Column {
                  visible: root.isCloudConnected && root.cloudCalendars.length > 0
                  width: parent.width
                  spacing: Style.space(8)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "CALENDAR VISIBILITY & FILTERS"
                      color: Qt.darker(root.contentForeground, 1.4)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 0.8
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "(Toggle on/off to filter events)"
                      color: Qt.darker(root.contentForeground, 2.0)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Column {
                    width: parent.width
                    spacing: Style.space(5)

                    Repeater {
                      model: root.cloudCalendars

                      Rectangle {
                        id: cloudCalCard
                        required property var modelData
                        readonly property bool isEnabled: !root.isCalendarDisabled(cloudCalCard.modelData.id)

                        width: parent.width
                        height: Style.space(38)
                        radius: Style.cornerRadius
                        color: cloudCalCard.isEnabled
                          ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                          : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.02)
                        border.width: 1
                        border.color: cloudCalCard.isEnabled
                          ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                          : "transparent"

                        Row {
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(10)
                          anchors.right: sw.left
                          anchors.rightMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)

                          Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: String(cloudCalCard.modelData.backgroundColor || Color.accent)
                            opacity: cloudCalCard.isEnabled ? 1.0 : 0.4
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(cloudCalCard.modelData.summary || "Calendar")
                            color: cloudCalCard.isEnabled ? root.contentForeground : Qt.darker(root.contentForeground, 2.0)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: !!cloudCalCard.modelData.primary
                            elide: Text.ElideRight
                            width: parent.width - 20
                          }
                        }

                        ToggleSwitch {
                          id: sw
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          checked: cloudCalCard.isEnabled
                          onToggled: root.toggleCalendarVisibility(cloudCalCard.modelData.id)
                        }
                      }
                    }
                  }
                }

                // Not Connected Actions (Has Credentials)
                Column {
                  visible: !root.isCloudConnected && root.hasClientCredentials && !root.showClientConfig
                  width: parent.width
                  spacing: Style.space(8)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      text: root.isWaitingAuth ? "Waiting for authorization..." : "Sign in with Google"
                      iconText: root.isWaitingAuth ? "󰑐" : "󰊭"
                      foreground: root.contentForeground
                      accent: Color.accent
                      onClicked: root.startGoogleAuth()
                    }

                    Button {
                      text: "Edit Client Credentials"
                      foreground: root.contentForeground
                      onClicked: root.showClientConfig = true
                    }
                  }

                  // If browser did not open automatically, show fallback button
                  Row {
                    visible: root.isWaitingAuth || root.currentAuthUrl !== ""
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      text: "Click Here to Open Login Page in Browser"
                      iconText: "󰌷"
                      foreground: root.contentForeground
                      onClicked: {
                        if (root.currentAuthUrl && Model.isValidGoogleAuthUrl(root.currentAuthUrl)) Quickshell.execDetached(["xdg-open", "--", root.currentAuthUrl])
                        else root.startGoogleAuth()
                      }
                    }
                  }
                }

                // Setup Credentials Form
                Column {
                  visible: !root.isCloudConnected && (!root.hasClientCredentials || root.showClientConfig)
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: "Enter your Google Cloud OAuth Client ID and Secret:"
                    color: Qt.darker(root.contentForeground, 1.3)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  TextField {
                    id: clientIdInput
                    width: parent.width
                    placeholderText: "Google Client ID (e.g. 123456789-xxx.apps.googleusercontent.com)"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                  }

                  TextField {
                    id: clientSecretInput
                    width: parent.width
                    placeholderText: "Google Client Secret (e.g. GOCSPX-...)"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    password: true
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      text: "Save & Connect"
                      iconText: "󰐕"
                      foreground: root.contentForeground
                      accent: Color.accent
                      onClicked: {
                        if (clientIdInput.text.trim() && clientSecretInput.text.trim()) {
                          root.setCredentials(clientIdInput.text.trim(), clientSecretInput.text.trim())
                          Qt.callLater(function() { root.startGoogleAuth() })
                        }
                      }
                    }

                    Button {
                      visible: root.hasClientCredentials
                      text: "Cancel"
                      foreground: root.contentForeground
                      onClicked: root.showClientConfig = false
                    }
                  }
                }
              }
            }

            // ==========================================
            // CARD 2: ICAL / ICS FEEDS (READ-ONLY)
            // ==========================================
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.calendars.length > 0

              Text {
                textFormat: Text.PlainText
                text: "CONNECTED ICAL FEEDS (" + root.calendars.length + ")"
                color: Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.8
                font.bold: true
              }

              Repeater {
                model: root.calendars

                Rectangle {
                  id: calRow
                  required property var modelData
                  width: parent.width
                  height: Style.space(42)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.right: delBtn.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(10)

                    Rectangle {
                      width: 12
                      height: 12
                      radius: 6
                      color: String(calRow.modelData.color || Color.accent)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - 24
                      spacing: 1

                      Text {
                        textFormat: Text.PlainText
                        text: String(calRow.modelData.name || "Calendar")
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: String(calRow.modelData.url || "")
                        color: Qt.darker(root.contentForeground, 2.0)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideMiddle
                        width: parent.width
                      }
                    }
                  }

                  PanelActionButton {
                    id: delBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰆴"
                    tooltipText: "Remove Calendar"
                    foreground: root.contentForeground
                    hoverColor: Color.urgent || "#EA4335"
                    fontFamily: root.contentFontFamily
                    onClicked: root.removeCalendar(calRow.modelData.id)
                  }
                }
              }
            }

            // Add iCal Feed Form
            Rectangle {
              width: parent.width
              implicitHeight: formColumn.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

              Column {
                id: formColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(10)

                property string selectedColor: Model.PRESET_COLORS[0]

                Text {
                  textFormat: Text.PlainText
                  text: "ADD ICAL / SECRET URL FEED"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  font.letterSpacing: 0.8
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  TextField {
                    id: calNameInput
                    width: Style.space(140)
                    placeholderText: "Name (e.g. Work)"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                  }

                  TextField {
                    id: calUrlInput
                    width: parent.width - calNameInput.width - Style.space(8)
                    placeholderText: "Paste Google Calendar iCal / Secret URL"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                  }
                }

                Item {
                  width: parent.width
                  height: addBtn.implicitHeight

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Repeater {
                      model: Model.PRESET_COLORS

                      Rectangle {
                        required property var modelData
                        width: 20
                        height: 20
                        radius: 10
                        color: String(modelData)
                        border.width: formColumn.selectedColor === modelData ? 2 : 0
                        border.color: root.contentForeground

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: formColumn.selectedColor = String(parent.modelData)
                        }
                      }
                    }
                  }

                  Button {
                    id: addBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add Feed"
                    iconText: "󰐕"
                    foreground: root.contentForeground
                    accent: Color.accent
                    onClicked: {
                      if (calUrlInput.text.trim()) {
                        root.addCalendar(calNameInput.text, calUrlInput.text, formColumn.selectedColor)
                        calNameInput.text = ""
                        calUrlInput.text = ""
                      }
                    }
                  }
                }
              }
            }
          }

          // Bottom Spacing
          Item {
            width: parent.width
            height: Style.space(8)
          }
        }
      }
    }

    // ==========================================
    // RECURRING EVENT DELETION MODAL DIALOG
    // ==========================================
    Rectangle {
      id: recurDeleteDialog
      visible: !!root.pendingDeleteEvent
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.72)
      z: 200

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.pendingDeleteEvent = null
      }

      Rectangle {
        width: Math.min(parent.width - Style.space(48), Style.space(460))
        implicitHeight: dlgCol.implicitHeight + Style.space(36)
        anchors.centerIn: parent
        radius: Style.cornerRadius > 0 ? 8 : 0
        color: Color.background || "#1e1e2e"
        border.width: 1
        border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)

        MouseArea {
          anchors.fill: parent
          // Block click-through to overlay
          onClicked: {}
        }

        Column {
          id: dlgCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(18)
          spacing: Style.space(14)

          // Header Row
          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: "󰆴"
              color: Color.urgent || "#EA4335"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              width: parent.width - Style.space(40)

              Text {
                textFormat: Text.PlainText
                text: "Delete Recurring Event"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.pendingDeleteEvent ? String(root.pendingDeleteEvent.summary || "Event") : ""
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "This is a repeating event. Which occurrences would you like to delete?"
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            width: parent.width
          }

          // Options List
          Column {
            width: parent.width
            spacing: Style.space(8)

            // Option 1: This event only
            Rectangle {
              width: parent.width
              height: Style.space(44)
              radius: Style.cornerRadius > 0 ? 6 : 0
              color: opt1Mouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: "󰄲"
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    textFormat: Text.PlainText
                    text: "This event only"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Only delete this occurrence on " + (root.pendingDeleteEvent ? String(root.pendingDeleteEvent.dateKey || "") : "")
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              MouseArea {
                id: opt1Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var ev = root.pendingDeleteEvent
                  root.pendingDeleteEvent = null
                  root.executeRecurringDelete(ev, "this_only")
                }
              }
            }

            // Option 2: This and all following events
            Rectangle {
              width: parent.width
              height: Style.space(44)
              radius: Style.cornerRadius > 0 ? 6 : 0
              color: opt2Mouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: "󰒭"
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    textFormat: Text.PlainText
                    text: "This and all following events"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Stop recurrence and remove all future occurrences"
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              MouseArea {
                id: opt2Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var ev = root.pendingDeleteEvent
                  root.pendingDeleteEvent = null
                  root.executeRecurringDelete(ev, "following")
                }
              }
            }

            // Option 3: All events in the series
            Rectangle {
              width: parent.width
              height: Style.space(44)
              radius: Style.cornerRadius > 0 ? 6 : 0
              color: opt3Mouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.urgent || "#EA4335") : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: "󰆴"
                  color: Color.urgent || "#EA4335"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    textFormat: Text.PlainText
                    text: "All events in the series"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Permanently delete every occurrence in the series"
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              MouseArea {
                id: opt3Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var ev = root.pendingDeleteEvent
                  root.pendingDeleteEvent = null
                  root.executeRecurringDelete(ev, "all_series")
                }
              }
            }
          }

          // Bottom Action Row
          Row {
            anchors.right: parent.right
            spacing: Style.space(8)

            Button {
              text: "Cancel"
              foreground: root.contentForeground
              onClicked: root.pendingDeleteEvent = null
            }
          }
        }
      }
    }
  }
}
