// Data helpers for wessel.better-emojis.
// Mirrors the stock EmojiSearch.js contract and adds categories,
// multi-word search, recents, and skin-tone handling.

var TONE_MODIFIERS = ["\uD83C\uDFFB", "\uD83C\uDFFC", "\uD83C\uDFFD", "\uD83C\uDFFE", "\uD83C\uDFFF"]

function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data)) return []
    for (var i = 0; i < data.length; i++) {
      var it = data[i]
      if (it) {
        it._kLower = String(it.k || "").toLowerCase()
        it._variantsStr = it.v ? JSON.stringify(it.v) : "[]"
      }
    }
    return data
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  return (item && item._kLower) ? item._kLower : String((item && item.k) || "").toLowerCase()
}

// Every whitespace-separated word must appear somewhere in the keywords.
function matchesQuery(item, words) {
  var haystack = keywordText(item)
  for (var i = 0; i < words.length; i++) {
    if (haystack.indexOf(words[i]) < 0) return false
  }
  return true
}

// filterEmojis(emojis, query, limit)          -> all categories
// filterEmojis(emojis, query, limit, category)-> one category ("recent" handled by caller)
function filterEmojis(emojis, query, limit, category) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var words = needle ? needle.split(/\s+/) : []
  var max = limit === undefined || limit === null ? 2000 : Number(limit)
  if (isNaN(max)) max = 2000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (category && item.c !== category) continue
    if (words.length && !matchesQuery(item, words)) continue
    out.push(item)
    if (out.length >= max) break
  }
  return out
}

// Ordered category list derived from the dataset.
function categories(emojis) {
  var values = Array.isArray(emojis) ? emojis : []
  var seen = {}
  var out = []
  for (var i = 0; i < values.length; i++) {
    var c = values[i] && values[i].c
    if (c && !seen[c]) {
      seen[c] = true
      out.push(c)
    }
  }
  return out
}

function toneModifier(tone) {
  var index = Number(tone)
  if (isNaN(index) || index < 1 || index > TONE_MODIFIERS.length) return ""
  return TONE_MODIFIERS[index - 1]
}

// Prefer the exact Unicode variant, falling back to appending a modifier for
// callers without generated variant data.
function applySkinTone(emoji, tone, variants) {
  var base = String(emoji || "")
  var modifier = toneModifier(tone)
  if (!modifier) return base
  var values = variants
  if (typeof values === "string") {
    try {
      values = JSON.parse(values)
    } catch (e) {
      values = []
    }
  }
  var index = Number(tone) - 1
  if (Array.isArray(values) && values[index]) return String(values[index])
  if (base.charCodeAt(base.length - 1) === 0xFE0F) base = base.slice(0, -1)
  return base + modifier
}

function supportsTone(item) {
  return !!(item && item.t)
}

// Remove every skin-tone modifier so toned recents can be looked up again.
function stripTones(emoji) {
  return String(emoji || "").replace(/\uD83C[\uDFFB-\uDFFF]/g, "")
}

// Recents are stored as plain emoji strings (tone already applied).
function pushRecent(recents, emoji, cap) {
  var list = Array.isArray(recents) ? recents.slice() : []
  var max = Number(cap) > 0 ? Number(cap) : 30
  var existing = list.indexOf(emoji)
  if (existing >= 0) list.splice(existing, 1)
  list.unshift(emoji)
  if (list.length > max) list.length = max
  return list
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis,
    categories: categories,
    toneModifier: toneModifier,
    applySkinTone: applySkinTone,
    supportsTone: supportsTone,
    stripTones: stripTones,
    pushRecent: pushRecent
  }
}
