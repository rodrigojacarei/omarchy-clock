// Pure date, calendar, and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node;
// the QML owns month/weekday naming through Qt.locale().

var MS_PER_DAY = 86400000

var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
var DAY_NAME_TO_INDEX = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 }

var PRESET_COLORS = [
  "#4285F4", // Google Blue
  "#34A853", // Google Green
  "#EA4335", // Google Red
  "#FBBC05", // Google Yellow
  "#9334E6", // Purple
  "#F97316", // Orange
  "#06B6D4", // Cyan
  "#EC4899"  // Pink
]

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  if (!date) return ""
  try {
    return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
  } catch (e) {
    return ""
  }
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

function monthGrid(year, month, weekStart, todayKey, eventsByDate) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var eventsMap = eventsByDate || {}
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      
      var dayEvents = eventsMap[key] || []
      var hasEvents = dayEvents.length > 0
      var eventColors = []
      for (var e = 0; e < dayEvents.length; e++) {
        var col = dayEvents[e].calendarColor || "#4285F4"
        if (eventColors.indexOf(col) === -1 && eventColors.length < 3) {
          eventColors.push(col)
        }
      }

      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        hasEvents: hasEvents,
        eventCount: dayEvents.length,
        eventColors: eventColors
      })
      cursor.setDate(cursor.getDate() + 1)
    }

    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// -------------------------------------------------------------
// Google Calendar / iCal (RFC 5545) Parsing & Event Management
// -------------------------------------------------------------

function unescapeIcsText(text) {
  if (!text) return ""
  return String(text)
    .replace(/\\n/g, "\n")
    .replace(/\\N/g, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\")
}

function parseIcsDate(propValue, params) {
  if (!propValue) return null
  var text = String(propValue).replace(/^\s+|\s+$/g, "")
  var isDateOnly = (params && params.indexOf("VALUE=DATE") !== -1) || /^\d{8}$/.test(text)

  if (isDateOnly) {
    var y = parseInt(text.substring(0, 4), 10)
    var m = parseInt(text.substring(4, 6), 10) - 1
    var d = parseInt(text.substring(6, 8), 10)
    var dateOnly = new Date(y, m, d, 0, 0, 0)
    return {
      date: dateOnly,
      allDay: true,
      year: y,
      month: m,
      day: d,
      key: dateKey(y, m, d)
    }
  }

  var match = text.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?/)
  if (!match) return null

  var yr = parseInt(match[1], 10)
  var mo = parseInt(match[2], 10) - 1
  var dy = parseInt(match[3], 10)
  var hr = parseInt(match[4], 10)
  var mn = parseInt(match[5], 10)
  var sc = parseInt(match[6], 10)
  var isUtc = match[7] === "Z"

  var dateObj = isUtc
    ? new Date(Date.UTC(yr, mo, dy, hr, mn, sc))
    : new Date(yr, mo, dy, hr, mn, sc)

  return {
    date: dateObj,
    allDay: false,
    year: dateObj.getFullYear(),
    month: dateObj.getMonth(),
    day: dateObj.getDate(),
    key: keyForDate(dateObj)
  }
}

function isValidHttpsUrl(urlString) {
  if (!urlString || typeof urlString !== "string") return false
  var clean = urlString.trim()
  if (clean.indexOf("https://") !== 0) return false
  if (/[\r\n\t\0\s<>"'`\\;\$|{}()^]/.test(clean)) return false
  var match = clean.match(/^https:\/\/([a-zA-Z0-9.-]+)(:[0-9]+)?(\/[a-zA-Z0-9_.~!*@&=+?#%/-]*)?$/)
  if (!match) return false
  var host = match[1]
  if (!host || host.indexOf("-") === 0 || host.lastIndexOf("-") === host.length - 1 || host.indexOf("..") !== -1) return false
  return true
}

function normalizeIcsUrl(url) {
  if (!url || typeof url !== "string") return ""
  var clean = url.trim()
  if (clean.indexOf("webcal://") === 0) {
    clean = "https://" + clean.substring(9)
  }
  return isValidHttpsUrl(clean) ? clean : ""
}

function isValidMeetingUrl(urlString) {
  if (!urlString || typeof urlString !== "string") return false
  var clean = urlString.trim()
  if (clean.indexOf("https://") !== 0) return false
  if (/[\r\n\t\0\s<>"'`\\;\$|{}()^]/.test(clean)) return false

  var match = clean.match(/^https:\/\/([a-zA-Z0-9.-]+)(:[0-9]+)?(\/[a-zA-Z0-9_.~!*@&=+?#%/-]*)?$/)
  if (!match) return false

  var host = match[1].toLowerCase()
  var allowedHosts = [
    "meet.google.com",
    "zoom.us",
    "teams.microsoft.com",
    "teams.live.com",
    "webex.com",
    "meet.jit.si"
  ]

  for (var i = 0; i < allowedHosts.length; i++) {
    var ah = allowedHosts[i]
    if (host === ah || host.endsWith("." + ah)) {
      return true
    }
  }
  return false
}

function isValidGoogleAuthUrl(urlString) {
  if (!urlString || typeof urlString !== "string") return false
  var clean = urlString.trim()
  if (clean.indexOf("https://accounts.google.com/") !== 0) return false
  if (/[\r\n\t\0\s<>"'`\\;\$|{}()^]/.test(clean)) return false
  return isValidHttpsUrl(clean)
}

function extractMeetUrl(text) {
  if (!text || typeof text !== "string") return ""
  var match = text.match(/https:\/\/(?:[a-zA-Z0-9.-]+\.)?(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|meet\.jit\.si)(?::[0-9]+)?\/[a-zA-Z0-9_.~!*@&=+?#%/-]*/i)
  if (match && isValidMeetingUrl(match[0])) {
    return match[0]
  }
  return ""
}

function generateMeetUrl() {
  var letters = "abcdefghijklmnopqrstuvwxyz"
  function rStr(len) {
    var res = ""
    for (var i = 0; i < len; i++) {
      res += letters.charAt(Math.floor(Math.random() * letters.length))
    }
    return res
  }
  return "https://meet.google.com/" + rStr(3) + "-" + rStr(4) + "-" + rStr(3)
}

function parseIcs(rawIcs, calendarMeta) {
  if (!rawIcs || typeof rawIcs !== "string") return []
  if (rawIcs.length > 5242880) return [] // Enforce 5MB strict byte cap
  if (rawIcs.indexOf("BEGIN:VCALENDAR") === -1) return []

  var meta = calendarMeta || {}
  var calName = meta.name || "Google Calendar"
  var calColor = meta.color || "#4285F4"

  try {
    var unfolded = String(rawIcs).replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "")
    var lines = unfolded.split(/\r?\n/)

    var defaultCalName = calName
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("X-WR-CALNAME:") === 0) {
        var parsedName = unescapeIcsText(line.substring(13).replace(/^\s+|\s+$/g, ""))
        if (parsedName && !meta.name) defaultCalName = parsedName
      }
    }

    var events = []
    var inEvent = false
    var currentEvent = null

    for (var j = 0; j < lines.length; j++) {
      var rawLine = lines[j]
      if (!rawLine) continue

      if (rawLine === "BEGIN:VEVENT") {
        inEvent = true
        currentEvent = {
          summary: "Untitled Event",
          description: "",
          location: "",
          dtstart: null,
          dtend: null,
          rrule: null,
          exdates: [],
          status: "",
          uid: "",
          calendarName: defaultCalName,
          calendarColor: calColor,
          meetUrl: ""
        }
        continue
      }

      if (rawLine === "END:VEVENT") {
        if (currentEvent && currentEvent.dtstart && currentEvent.dtstart.date && currentEvent.status !== "CANCELLED") {
          if (!currentEvent.meetUrl) {
            currentEvent.meetUrl = extractMeetUrl(currentEvent.description) || extractMeetUrl(currentEvent.location)
          }
          events.push(currentEvent)
        }
        inEvent = false
        currentEvent = null
        continue
      }

      if (!inEvent || !currentEvent) continue

      var colonIdx = rawLine.indexOf(":")
      if (colonIdx === -1) continue

      var propPart = rawLine.substring(0, colonIdx)
      var valPart = rawLine.substring(colonIdx + 1)

      var propSplit = propPart.split(";")
      var propName = propSplit[0].toUpperCase()
      var propParams = propSplit.slice(1).join(";")

      switch (propName) {
        case "SUMMARY":
          currentEvent.summary = unescapeIcsText(valPart)
          break
        case "DESCRIPTION":
          currentEvent.description = unescapeIcsText(valPart)
          break
        case "LOCATION":
          currentEvent.location = unescapeIcsText(valPart)
          break
        case "STATUS":
          currentEvent.status = valPart.replace(/^\s+|\s+$/g, "").toUpperCase()
          break
        case "UID":
          currentEvent.uid = valPart.replace(/^\s+|\s+$/g, "")
          break
        case "DTSTART":
          currentEvent.dtstart = parseIcsDate(valPart, propParams)
          break
        case "DTEND":
          currentEvent.dtend = parseIcsDate(valPart, propParams)
          break
        case "RRULE":
          currentEvent.rrule = valPart.replace(/^\s+|\s+$/g, "")
          break
        case "EXDATE":
          var exDates = valPart.split(",")
          for (var k = 0; k < exDates.length; k++) {
            var parsedEx = parseIcsDate(exDates[k], propParams)
            if (parsedEx && parsedEx.key) currentEvent.exdates.push(parsedEx.key)
          }
          break
        case "URL":
          var cleanVal = valPart.replace(/^\s+|\s+$/g, "")
          if (!currentEvent.meetUrl && isValidMeetingUrl(cleanVal)) {
            currentEvent.meetUrl = cleanVal
          }
          break
      }
    }

    return events
  } catch (err) {
    return []
  }
}

function parseRRule(rruleStr) {
  if (!rruleStr) return null
  try {
    var parts = rruleStr.split(";")
    var rule = {
      freq: "",
      interval: 1,
      until: null,
      count: 0,
      byDay: []
    }

    for (var i = 0; i < parts.length; i++) {
      var pair = parts[i].split("=")
      if (pair.length !== 2) continue
      var key = pair[0].toUpperCase()
      var val = pair[1].toUpperCase()

      if (key === "FREQ") rule.freq = val
      else if (key === "INTERVAL") rule.interval = parseInt(val, 10) || 1
      else if (key === "UNTIL") rule.until = parseIcsDate(val)
      else if (key === "COUNT") rule.count = parseInt(val, 10) || 0
      else if (key === "BYDAY") rule.byDay = val.split(",")
      else if (key === "BYMONTHDAY") rule.byMonthDay = parseInt(val, 10)
    }

    return rule
  } catch (e) {
    return null
  }
}

function formatTimeString(date, is24h) {
  if (!date) return ""
  try {
    var h = date.getHours()
    var m = date.getMinutes()
    var mStr = pad2(m)
    if (is24h) {
      return pad2(h) + ":" + mStr
    }
    var ampm = h >= 12 ? "PM" : "AM"
    var h12 = h % 12 || 12
    return h12 + ":" + mStr + " " + ampm
  } catch (e) {
    return ""
  }
}

function formatEventTime(startDt, endDt, allDay, is24h) {
  if (allDay) return "All day"
  if (!startDt || !startDt.date) return ""
  var startStr = formatTimeString(startDt.date, is24h)
  if (!endDt || !endDt.date) return startStr
  var endStr = formatTimeString(endDt.date, is24h)
  return startStr + " - " + endStr
}

function expandEvents(rawEvents, minKey, maxKey, is24h) {
  var result = []
  if (!rawEvents || !Array.isArray(rawEvents) || rawEvents.length === 0) return result

  try {
    var minParts = String(minKey || "2000-01-01").split("-")
    var minDate = new Date(parseInt(minParts[0], 10), parseInt(minParts[1], 10) - 1, parseInt(minParts[2], 10), 0, 0, 0)
    var maxParts = String(maxKey || "2099-12-31").split("-")
    var maxDate = new Date(parseInt(maxParts[0], 10), parseInt(maxParts[1], 10) - 1, parseInt(maxParts[2], 10), 23, 59, 59)

    for (var i = 0; i < rawEvents.length; i++) {
      var ev = rawEvents[i]
      if (!ev || !ev.dtstart || !ev.dtstart.date) continue

      var start = ev.dtstart
      var end = ev.dtend
      var durationMs = end && end.date ? (end.date.getTime() - start.date.getTime()) : 0

      if (!ev.rrule) {
        if (start.allDay && end && end.date) {
          var cur = new Date(start.date)
          var safety = 0
          while (cur < end.date && safety < 366) {
            safety++
            var k = keyForDate(cur)
            if (k >= minKey && k <= maxKey && ev.exdates.indexOf(k) === -1) {
              result.push({
                id: (ev.uid || "") + "_" + k,
                uid: ev.uid,
                summary: ev.summary,
                description: ev.description,
                location: ev.location,
                meetUrl: ev.meetUrl,
                calendarName: ev.calendarName,
                calendarColor: ev.calendarColor,
                allDay: true,
                dateKey: k,
                startTime: "00:00",
                timeDisplay: "All day",
                originalStart: start.date
              })
            }
            cur.setDate(cur.getDate() + 1)
          }
        } else {
          var key = start.key
          if (key >= minKey && key <= maxKey && ev.exdates.indexOf(key) === -1) {
            result.push({
              id: (ev.uid || "") + "_" + key,
              uid: ev.uid,
              summary: ev.summary,
              description: ev.description,
              location: ev.location,
              meetUrl: ev.meetUrl,
              calendarName: ev.calendarName,
              calendarColor: ev.calendarColor,
              allDay: start.allDay,
              dateKey: key,
              startTime: start.allDay ? "00:00" : formatTimeString(start.date, true),
              endTime: (start.allDay || !end || !end.date) ? "23:59" : formatTimeString(end.date, true),
              timeDisplay: formatEventTime(start, end, start.allDay, is24h),
              originalStart: start.date
            })
          }
        }
        continue
      }

      var rule = parseRRule(ev.rrule)
      if (!rule) continue

      var cursor = new Date(start.date)
      var count = 0
      var maxIterations = 500
      var iterations = 0
      var untilDate = rule.until && rule.until.date ? rule.until.date : maxDate

      if (rule.freq === "DAILY") {
        while (cursor <= maxDate && cursor <= untilDate && iterations < maxIterations) {
          iterations++
          if (rule.count > 0 && count >= rule.count) break
          var dKey = keyForDate(cursor)
          if (cursor >= minDate && dKey >= minKey && dKey <= maxKey && ev.exdates.indexOf(dKey) === -1) {
            var occStart = new Date(cursor)
            var occEnd = new Date(occStart.getTime() + durationMs)
            result.push({
              id: (ev.uid || "") + "_" + dKey,
              uid: ev.uid,
              summary: ev.summary,
              description: ev.description,
              location: ev.location,
              meetUrl: ev.meetUrl,
              calendarName: ev.calendarName,
              calendarColor: ev.calendarColor,
              allDay: start.allDay,
              dateKey: dKey,
              startTime: start.allDay ? "00:00" : formatTimeString(occStart, true),
              endTime: start.allDay ? "23:59" : formatTimeString(occEnd, true),
              timeDisplay: formatEventTime({ date: occStart, allDay: start.allDay }, { date: occEnd, allDay: start.allDay }, start.allDay, is24h),
              originalStart: occStart
            })
          }
          count++
          cursor.setDate(cursor.getDate() + (rule.interval || 1))
        }
      } else if (rule.freq === "WEEKLY") {
        var byDays = []
        if (rule.byDay && rule.byDay.length > 0) {
          for (var b = 0; b < rule.byDay.length; b++) {
            var code = rule.byDay[b].replace(/^[+-]?\d+/, "")
            if (DAY_NAME_TO_INDEX[code] !== undefined) byDays.push(DAY_NAME_TO_INDEX[code])
          }
        }
        if (byDays.length === 0) byDays.push(start.date.getDay())

        var weekCursor = new Date(cursor)
        weekCursor.setDate(weekCursor.getDate() - weekCursor.getDay())

        while (weekCursor <= maxDate && weekCursor <= untilDate && iterations < maxIterations) {
          iterations++
          for (var dayIdx = 0; dayIdx < 7; dayIdx++) {
            var dayDate = new Date(weekCursor)
            dayDate.setDate(dayDate.getDate() + dayIdx)
            if (dayDate < start.date) continue
            if (dayDate > maxDate || dayDate > untilDate) break

            if (byDays.indexOf(dayDate.getDay()) !== -1) {
              if (rule.count > 0 && count >= rule.count) break
              var wKey = keyForDate(dayDate)
              if (dayDate >= minDate && wKey >= minKey && wKey <= maxKey && ev.exdates.indexOf(wKey) === -1) {
                var wOccStart = new Date(dayDate)
                wOccStart.setHours(start.date.getHours(), start.date.getMinutes(), start.date.getSeconds())
                var wOccEnd = new Date(wOccStart.getTime() + durationMs)
                result.push({
                  id: (ev.uid || "") + "_" + wKey,
                  uid: ev.uid,
                  summary: ev.summary,
                  description: ev.description,
                  location: ev.location,
                  meetUrl: ev.meetUrl,
                  calendarName: ev.calendarName,
                  calendarColor: ev.calendarColor,
                  allDay: start.allDay,
                  dateKey: wKey,
                  startTime: start.allDay ? "00:00" : formatTimeString(wOccStart, true),
                  endTime: start.allDay ? "23:59" : formatTimeString(wOccEnd, true),
                  timeDisplay: formatEventTime({ date: wOccStart, allDay: start.allDay }, { date: wOccEnd, allDay: start.allDay }, start.allDay, is24h),
                  originalStart: wOccStart
                })
              }
              count++
            }
          }
          weekCursor.setDate(weekCursor.getDate() + 7 * (rule.interval || 1))
        }
      } else if (rule.freq === "MONTHLY") {
        var startYear = start.date.getFullYear()
        var startMonth = start.date.getMonth()
        var startHours = start.date.getHours()
        var startMinutes = start.date.getMinutes()
        var startSeconds = start.date.getSeconds()

        var curYear = startYear
        var curMonth = startMonth

        while (iterations < maxIterations) {
          iterations++
          if (rule.count > 0 && count >= rule.count) break

          var monthStartDate = new Date(curYear, curMonth, 1)
          if (monthStartDate > maxDate || monthStartDate > untilDate) break

          var daysToEmit = []

          if (rule.byMonthDay) {
            var maxDays = new Date(curYear, curMonth + 1, 0).getDate()
            var targetDay = rule.byMonthDay
            if (targetDay <= maxDays) {
              daysToEmit.push(targetDay)
            }
          } else if (rule.byDay && rule.byDay.length > 0) {
            for (var b = 0; b < rule.byDay.length; b++) {
              var dayToken = rule.byDay[b]
              var match = dayToken.match(/^(-?[0-9]+)?([A-Z]{2})$/)
              if (match) {
                var nth = match[1] ? parseInt(match[1], 10) : 1
                var wCode = match[2]
                var dNum = getNthWeekdayOfMonth(curYear, curMonth, nth, wCode)
                if (dNum !== null) daysToEmit.push(dNum)
              }
            }
          } else {
            var mDays = new Date(curYear, curMonth + 1, 0).getDate()
            var sDay = start.date.getDate()
            if (sDay <= mDays) daysToEmit.push(sDay)
          }

          daysToEmit.sort(function(a, b) { return a - b })

          for (var d = 0; d < daysToEmit.length; d++) {
            var dVal = daysToEmit[d]
            var occDate = new Date(curYear, curMonth, dVal, startHours, startMinutes, startSeconds)

            if (occDate < start.date) continue
            if (occDate > untilDate || occDate > maxDate) break
            if (rule.count > 0 && count >= rule.count) break

            var mKey = keyForDate(occDate)
            if (occDate >= minDate && mKey >= minKey && mKey <= maxKey && (!ev.exdates || ev.exdates.indexOf(mKey) === -1)) {
              var mOccStart = occDate
              var mOccEnd = new Date(mOccStart.getTime() + durationMs)
              result.push({
                id: (ev.uid || "") + "_" + mKey,
                uid: ev.uid,
                summary: ev.summary,
                description: ev.description,
                location: ev.location,
                meetUrl: ev.meetUrl,
                calendarName: ev.calendarName,
                calendarColor: ev.calendarColor,
                allDay: start.allDay,
                dateKey: mKey,
                startTime: start.allDay ? "00:00" : formatTimeString(mOccStart, true),
                endTime: start.allDay ? "23:59" : formatTimeString(mOccEnd, true),
                timeDisplay: formatEventTime({ date: mOccStart, allDay: start.allDay }, { date: mOccEnd, allDay: start.allDay }, start.allDay, is24h),
                originalStart: mOccStart
              })
            }
            count++
          }

          var interval = rule.interval || 1
          curMonth += interval
          while (curMonth >= 12) {
            curMonth -= 12
            curYear += 1
          }
        }
      } else if (rule.freq === "YEARLY") {
        while (cursor <= maxDate && cursor <= untilDate && iterations < maxIterations) {
          iterations++
          if (rule.count > 0 && count >= rule.count) break
          var yKey = keyForDate(cursor)
          if (cursor >= minDate && yKey >= minKey && yKey <= maxKey && ev.exdates.indexOf(yKey) === -1) {
            var yOccStart = new Date(cursor)
            var yOccEnd = new Date(yOccStart.getTime() + durationMs)
            result.push({
              id: (ev.uid || "") + "_" + yKey,
              uid: ev.uid,
              summary: ev.summary,
              description: ev.description,
              location: ev.location,
              meetUrl: ev.meetUrl,
              calendarName: ev.calendarName,
              calendarColor: ev.calendarColor,
              allDay: start.allDay,
              dateKey: yKey,
              startTime: start.allDay ? "00:00" : formatTimeString(yOccStart, true),
              endTime: start.allDay ? "23:59" : formatTimeString(yOccEnd, true),
              timeDisplay: formatEventTime({ date: yOccStart, allDay: start.allDay }, { date: yOccEnd, allDay: start.allDay }, start.allDay, is24h),
              originalStart: yOccStart
            })
          }
          count++
          cursor.setFullYear(cursor.getFullYear() + (rule.interval || 1))
        }
      }
    }

    result.sort(function(a, b) {
      if (a.dateKey !== b.dateKey) return a.dateKey.localeCompare(b.dateKey)
      if (a.allDay && !b.allDay) return -1
      if (!a.allDay && b.allDay) return 1
      return a.startTime.localeCompare(b.startTime)
    })

    return result
  } catch (err) {
    return result
  }
}

function groupEventsByDate(expandedList) {
  var map = {}
  if (!expandedList || !Array.isArray(expandedList)) return map
  for (var i = 0; i < expandedList.length; i++) {
    var item = expandedList[i]
    if (!item || !item.dateKey) continue
    if (!map[item.dateKey]) map[item.dateKey] = []
    map[item.dateKey].push(item)
  }
  return map
}

function gridDateRange(viewYear, viewMonth, weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(viewYear, viewMonth, 1).getDay() - start + 7) % 7
  var firstCell = new Date(viewYear, viewMonth, 1 - leading)
  var lastCell = new Date(firstCell.getFullYear(), firstCell.getMonth(), firstCell.getDate() + 41)
  return {
    minKey: keyForDate(firstCell),
    maxKey: keyForDate(lastCell)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    isValidHttpsUrl: isValidHttpsUrl,
    normalizeIcsUrl: normalizeIcsUrl,
    isValidMeetingUrl: isValidMeetingUrl,
    isValidGoogleAuthUrl: isValidGoogleAuthUrl,
    parseIcs: parseIcs,
    parseIcsDate: parseIcsDate,
    parseRRule: parseRRule,
    expandEvents: expandEvents,
    groupEventsByDate: groupEventsByDate,
    gridDateRange: gridDateRange,
    extractMeetUrl: extractMeetUrl,
    generateMeetUrl: generateMeetUrl,
    formatEventTime: formatEventTime,
    PRESET_COLORS: PRESET_COLORS
  }
}

function parseGoogleApiEvents(apiItems, calColor) {
  var events = []
  if (!apiItems || !Array.isArray(apiItems)) return events
  for (var i = 0; i < apiItems.length; i++) {
    var it = apiItems[i]
    if (!it || it.status === "cancelled") continue

    var isAllDay = false
    var dKey = ""
    var startT = "00:00"
    var timeDisp = "All day"
    var origStart = new Date()

    if (it.start) {
      if (it.start.date) {
        isAllDay = true
        dKey = it.start.date
        var p = it.start.date.split("-")
        if (p.length === 3) origStart = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
      } else if (it.start.dateTime) {
        isAllDay = false
        var dt = new Date(it.start.dateTime)
        origStart = dt
        dKey = keyForDate(dt)
        startT = formatTimeString(dt, true)
        var endStr = it.end && it.end.dateTime ? formatTimeString(new Date(it.end.dateTime), true) : ""
        timeDisp = startT + (endStr ? (" - " + endStr) : "")
      }
    }

    if (!dKey) continue

    var meet = (it.hangoutLink && isValidMeetingUrl(it.hangoutLink)) ? it.hangoutLink : ""
    if (!meet && it.conferenceData && it.conferenceData.entryPoints) {
      for (var ep = 0; ep < it.conferenceData.entryPoints.length; ep++) {
        var entry = it.conferenceData.entryPoints[ep]
        if (entry && entry.uri && isValidMeetingUrl(entry.uri)) {
          meet = entry.uri
          break
        }
      }
    }
    if (!meet) {
      meet = extractMeetUrl(it.location) || extractMeetUrl(it.description)
    }

    var cName = it.calendarName || "Google Calendar"
    var cColor = it.calendarColor || calColor || "#4285F4"

    var cId = it.calendarId || (it.organizer ? it.organizer.email : "") || ""
    var isRecur = !!it.recurringEventId || (it.recurrence && it.recurrence.length > 0)
    events.push({
      id: it.id,
      uid: it.id,
      masterId: it.recurringEventId || it.id,
      recurringEventId: it.recurringEventId || "",
      isRecurring: isRecur,
      summary: it.summary || "Untitled Event",
      description: it.description || "",
      location: it.location || "",
      meetUrl: meet,
      calendarId: cId,
      calendarName: cName,
      calendarColor: cColor,
      allDay: isAllDay,
      dateKey: dKey,
      startTime: startT,
      endTime: isAllDay ? "23:59" : (endStr || ""),
      timeDisplay: timeDisp,
      originalStart: origStart,
      isCloud: true
    })
  }
  return events
}

if (typeof module !== "undefined" && module.exports) {
  module.exports.parseGoogleApiEvents = parseGoogleApiEvents
}

function findNextEvent(events, now) {
  if (!events || !Array.isArray(events) || events.length === 0) return null
  var todayDate = now || new Date()
  var todayKey = keyForDate(todayDate)
  var currentMinutes = todayDate.getHours() * 60 + todayDate.getMinutes()

  var upcoming = []

  for (var i = 0; i < events.length; i++) {
    var ev = events[i]
    if (!ev || ev.dateKey !== todayKey || ev.allDay) continue

    var startParts = (ev.startTime || "00:00").split(":")
    var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)

    // Strictly upcoming in the future (starts after the current minute)
    if (startMin > currentMinutes) {
      upcoming.push({
        event: ev,
        minutes: startMin
      })
    }
  }

  if (upcoming.length === 0) return null

  // Sort by earliest start time
  upcoming.sort(function(a, b) {
    return a.minutes - b.minutes
  })

  return upcoming[0].event
}

if (typeof module !== "undefined" && module.exports) {
  module.exports.findNextEvent = findNextEvent
}

function nextEventLabel(ev, now) {
  if (!ev) return ""
  var todayDate = now || new Date()
  var currentMinutes = todayDate.getHours() * 60 + todayDate.getMinutes()

  var startParts = (ev.startTime || "00:00").split(":")
  var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)
  var diff = startMin - currentMinutes

  var timeStr = ""
  if (diff <= 0) timeStr = "now"
  else if (diff === 1) timeStr = "1 min"
  else if (diff < 60) timeStr = diff + " min"
  else {
    var hrs = Math.floor(diff / 60)
    var rem = diff % 60
    if (rem === 0) timeStr = hrs + "h"
    else timeStr = hrs + "h " + rem + "m"
  }

  var title = String(ev.summary || "Event").trim()
  return title + " in " + timeStr
}

if (typeof module !== "undefined" && module.exports) {
  module.exports.nextEventLabel = nextEventLabel
}

function getRecurrenceOptions(date) {
  var d = date || new Date()
  var dayOfWeek = d.getDay()
  var dayOfMonth = d.getDate()
  var month = d.getMonth()

  var WEEKDAY_CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
  var WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  var MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  var NTH_NAMES = ["", "1st", "2nd", "3rd", "4th", "5th"]

  var wCode = WEEKDAY_CODES[dayOfWeek]
  var wName = WEEKDAY_NAMES[dayOfWeek]
  var mName = MONTH_NAMES[month]
  var nth = Math.floor((dayOfMonth - 1) / 7) + 1
  var nthName = NTH_NAMES[nth] || (nth + "th")
  var nthCode = nth + wCode

  return [
    { label: "Does not repeat", rrule: "" },
    { label: "Every day", rrule: "RRULE:FREQ=DAILY" },
    { label: "Every week on " + wName, rrule: "RRULE:FREQ=WEEKLY;BYDAY=" + wCode },
    { label: "Every month on day " + dayOfMonth, rrule: "RRULE:FREQ=MONTHLY;BYMONTHDAY=" + dayOfMonth },
    { label: "Every month on the " + nthName + " " + wName, rrule: "RRULE:FREQ=MONTHLY;BYDAY=" + nthCode },
    { label: "Every year on " + mName + " " + dayOfMonth, rrule: "RRULE:FREQ=YEARLY" }
  ]
}

if (typeof module !== "undefined" && module.exports) {
  module.exports.getRecurrenceOptions = getRecurrenceOptions
}

function weekdayCodeForDate(date) {
  var d = date || new Date()
  var WEEKDAY_CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
  return WEEKDAY_CODES[d.getDay()] || "MO"
}

function buildCustomRrule(config) {
  if (!config || !config.freq) return ""
  var parts = ["FREQ=" + config.freq]

  var interval = parseInt(config.interval, 10) || 1
  if (interval > 1) parts.push("INTERVAL=" + interval)

  if (config.freq === "WEEKLY") {
    if (config.weekdays && config.weekdays.length > 0) {
      parts.push("BYDAY=" + config.weekdays.join(","))
    }
  } else if (config.freq === "MONTHLY") {
    if (config.monthlyType === "nthWeekday") {
      var nthPrefix = config.nthIndex === -1 ? "-1" : String(config.nthIndex || 1)
      parts.push("BYDAY=" + nthPrefix + (config.nthWeekday || "MO"))
    } else {
      var mDay = parseInt(config.monthDay, 10) || 1
      parts.push("BYMONTHDAY=" + mDay)
    }
  }

  if (config.endType === "count" && config.count) {
    var cnt = parseInt(config.count, 10)
    if (cnt > 0) parts.push("COUNT=" + cnt)
  } else if (config.endType === "until" && config.untilDate) {
    var cleanUntil = String(config.untilDate).replace(/[^0-9]/g, "").slice(0, 8)
    if (cleanUntil.length === 8) {
      parts.push("UNTIL=" + cleanUntil + "T235959Z")
    }
  }

  return "RRULE:" + parts.join(";")
}

function describeRrule(rruleStr) {
  if (!rruleStr) return "Does not repeat"
  var clean = rruleStr.replace(/^RRULE:/i, "")
  var dict = {}
  clean.split(";").forEach(function(pair) {
    var p = pair.split("=")
    if (p[0]) dict[p[0].toUpperCase()] = p[1] || ""
  })

  var freq = dict["FREQ"] || "DAILY"
  var interval = parseInt(dict["INTERVAL"] || "1", 10)
  var byday = dict["BYDAY"] || ""
  var bymonthday = dict["BYMONTHDAY"] || ""
  var count = dict["COUNT"] || ""
  var until = dict["UNTIL"] || ""

  var DAY_MAP = { SU: "Sunday", MO: "Monday", TU: "Tuesday", WE: "Wednesday", TH: "Thursday", FR: "Friday", SA: "Saturday" }
  var NTH_MAP = { "1": "1st", "2": "2nd", "3": "3rd", "4": "4th", "5": "5th", "-1": "last" }

  var desc = ""
  if (freq === "DAILY") {
    desc = interval === 1 ? "Every day" : "Every " + interval + " days"
  } else if (freq === "WEEKLY") {
    var days = byday ? byday.split(",").map(function(d) { return DAY_MAP[d] || d }).join(", ") : ""
    desc = interval === 1 ? "Every week" : "Every " + interval + " weeks"
    if (days) desc += " on " + days
  } else if (freq === "MONTHLY") {
    desc = interval === 1 ? "Every month" : "Every " + interval + " months"
    if (bymonthday) {
      desc += " on day " + bymonthday
    } else if (byday) {
      var match = byday.match(/^(-?[0-9]+)([A-Z]{2})$/)
      if (match) {
        var nth = NTH_MAP[match[1]] || (match[1] + "th")
        var dayName = DAY_MAP[match[2]] || match[2]
        desc += " on the " + nth + " " + dayName
      }
    }
  } else if (freq === "YEARLY") {
    desc = interval === 1 ? "Every year" : "Every " + interval + " years"
  }

  if (count) {
    desc += " (" + count + " times)"
  } else if (until) {
    var yr = until.slice(0, 4)
    var mo = until.slice(4, 6)
    var dy = until.slice(6, 8)
    desc += " (until " + yr + "-" + mo + "-" + dy + ")"
  }

  return desc || "Custom recurrence"
}

function stopRRuleBefore(rruleStr, dateKey) {
  if (!rruleStr) return ""
  var clean = rruleStr.replace(/^RRULE:/i, "")
  var parts = clean.split(";")
  var filtered = []
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    if (p.indexOf("UNTIL=") !== 0 && p.indexOf("COUNT=") !== 0 && p.length > 0) {
      filtered.push(p)
    }
  }
  var partsKey = String(dateKey || "").split("-")
  if (partsKey.length === 3) {
    var d = new Date(Date.UTC(parseInt(partsKey[0], 10), parseInt(partsKey[1], 10) - 1, parseInt(partsKey[2], 10), 0, 0, 0))
    d.setUTCDate(d.getUTCDate() - 1)
    var untilStr = d.getUTCFullYear() + pad2(d.getUTCMonth() + 1) + pad2(d.getUTCDate()) + "T235959Z"
    filtered.push("UNTIL=" + untilStr)
  }
  return "RRULE:" + filtered.join(";")
}

function findNotificationEvents(events, nowDate, leadMinutes, notifyAtStart, notifiedMap) {
  var alerts = []
  if (!events || !Array.isArray(events) || events.length === 0) return alerts
  var todayDate = nowDate || new Date()
  var todayKey = keyForDate(todayDate)
  var curMinutes = todayDate.getHours() * 60 + todayDate.getMinutes()
  var map = notifiedMap || {}
  var lead = parseInt(leadMinutes, 10)
  if (isNaN(lead) || lead < 0) lead = 10

  for (var i = 0; i < events.length; i++) {
    var ev = events[i]
    if (!ev || ev.dateKey !== todayKey || ev.allDay) continue

    var startParts = (ev.startTime || "00:00").split(":")
    var startMin = parseInt(startParts[0], 10) * 60 + parseInt(startParts[1] || "0", 10)
    var diff = startMin - curMinutes

    // 1. Lead time notification (e.g. 10 minutes before)
    if (lead > 0 && diff === lead) {
      var leadKey = (ev.id || ("ev_" + i)) + "_" + todayKey + "_lead_" + lead
      if (!map[leadKey]) {
        alerts.push({
          event: ev,
          type: "lead",
          diff: diff,
          notificationKey: leadKey
        })
      }
    }

    // 2. Start time notification (diff === 0)
    if (notifyAtStart && diff === 0) {
      var startKey = (ev.id || ("ev_" + i)) + "_" + todayKey + "_start"
      if (!map[startKey]) {
        alerts.push({
          event: ev,
          type: "start",
          diff: 0,
          notificationKey: startKey
        })
      }
    }
  }

  return alerts
}

if (typeof module !== "undefined" && module.exports) {
  module.exports.weekdayCodeForDate = weekdayCodeForDate
  module.exports.buildCustomRrule = buildCustomRrule
  module.exports.stopRRuleBefore = stopRRuleBefore
  module.exports.describeRrule = describeRrule
  module.exports.getNthWeekdayOfMonth = getNthWeekdayOfMonth
  module.exports.findNotificationEvents = findNotificationEvents
}

function getNthWeekdayOfMonth(year, month, nth, weekdayCode) {
  var DAY_MAP = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 }
  var targetDay = DAY_MAP[weekdayCode]
  if (targetDay === undefined) return null
  var maxDays = new Date(year, month + 1, 0).getDate()

  if (nth === -1) {
    var lastDayOfMonth = new Date(year, month + 1, 0)
    var lastDayIndex = lastDayOfMonth.getDay()
    var offset = (lastDayIndex - targetDay + 7) % 7
    return lastDayOfMonth.getDate() - offset
  }

  var firstDayIndex = new Date(year, month, 1).getDay()
  var offset = (targetDay - firstDayIndex + 7) % 7
  var targetDate = 1 + offset + (nth - 1) * 7
  if (targetDate <= maxDays) return targetDate
  return null
}
