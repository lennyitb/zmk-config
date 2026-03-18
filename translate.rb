#!/usr/bin/env ruby
# frozen_string_literal: true

# ZMK Keymap Dvorak Translator
#
# Translates ZMK .keymap files between:
#   WYSIWYG mode - keycodes show what appears on screen with macOS Dvorak
#   ANSI mode    - keycodes show what ZMK must send for Dvorak to produce desired output
#
# Usage:
#   ruby translate.rb --to-ansi input.keymap       # WYSIWYG -> ANSI (for flashing)
#   ruby translate.rb --to-wysiwyg input.keymap     # ANSI -> WYSIWYG (for reading)
#   ruby translate.rb --to-wysiwyg input.keymap -o out.keymap
#   ruby translate.rb --to-wysiwyg input.keymap -i  # modify in place
#   ruby translate.rb --test                         # run self-tests

require "optparse"

# What macOS Dvorak outputs for each QWERTY scancode (ZMK canonical names).
# Only keys that actually change are listed.
QWERTY_TO_DVORAK = {
  "Q" => "SQT",     "W" => "COMMA",  "E" => "DOT",    "R" => "P",
  "T" => "Y",       "Y" => "F",      "U" => "G",      "I" => "C",
  "O" => "R",       "P" => "L",      "S" => "O",      "D" => "E",
  "F" => "U",       "G" => "I",      "H" => "D",      "J" => "H",
  "K" => "T",       "L" => "N",      "Z" => "SEMI",   "X" => "Q",
  "C" => "J",       "V" => "K",      "B" => "X",      "N" => "B",
  "SEMI" => "S",    "SQT" => "MINUS",
  "MINUS" => "LBKT", "EQUAL" => "RBKT",
  "LBKT" => "FSLH",  "RBKT" => "EQUAL",
  "COMMA" => "W",   "DOT" => "V",    "FSLH" => "Z",
}.freeze

DVORAK_TO_QWERTY = QWERTY_TO_DVORAK.invert.freeze

# ZMK keycode aliases -> canonical short form used in the translation table.
ALIASES = {
  "SEMICOLON" => "SEMI", "SCLN" => "SEMI",
  "SINGLE_QUOTE" => "SQT", "APOSTROPHE" => "SQT", "APOS" => "SQT", "QUOT" => "SQT",
  "LEFT_BRACKET" => "LBKT",
  "RIGHT_BRACKET" => "RBKT",
  "BACKSLASH" => "BSLH",
  "GRAV" => "GRAVE",
  "CMMA" => "COMMA",
  "PERIOD" => "DOT",
  "SLASH" => "FSLH",
  "EQL" => "EQUAL",
  "NUMBER_1" => "N1", "NUM_1" => "N1",
  "NUMBER_2" => "N2", "NUM_2" => "N2",
  "NUMBER_3" => "N3", "NUM_3" => "N3",
  "NUMBER_4" => "N4", "NUM_4" => "N4",
  "NUMBER_5" => "N5", "NUM_5" => "N5",
  "NUMBER_6" => "N6", "NUM_6" => "N6",
  "NUMBER_7" => "N7", "NUM_7" => "N7",
  "NUMBER_8" => "N8", "NUM_8" => "N8",
  "NUMBER_9" => "N9", "NUM_9" => "N9",
  "NUMBER_0" => "N0", "NUM_0" => "N0",
}.freeze

# Shifted-character aliases -> their unshifted base key.
# e.g., UNDERSCORE means LS(MINUS).
SHIFTED_ALIASES = {
  "UNDERSCORE" => "MINUS", "UNDER" => "MINUS",
  "PLUS" => "EQUAL",
  "LEFT_BRACE" => "LBKT", "LBRC" => "LBKT", "LCUR" => "LBKT",
  "RIGHT_BRACE" => "RBKT", "RBRC" => "RBKT", "RCUR" => "RBKT",
  "PIPE" => "BSLH", "PIPE2" => "BSLH",
  "COLON" => "SEMI", "COLN" => "SEMI",
  "DOUBLE_QUOTES" => "SQT", "DQT" => "SQT",
  "TILDE" => "GRAVE", "TILD" => "GRAVE",
  "LESS_THAN" => "COMMA", "LABT" => "COMMA",
  "GREATER_THAN" => "DOT", "RABT" => "DOT",
  "QUESTION" => "FSLH", "QMARK" => "FSLH",
  "EXCLAMATION" => "N1", "EXCL" => "N1", "BANG" => "N1",
  "AT_SIGN" => "N2", "AT" => "N2", "ATSN" => "N2",
  "HASH" => "N3", "POUND" => "N3",
  "DOLLAR" => "N4", "DLLR" => "N4",
  "PERCENT" => "N5", "PRCNT" => "N5", "PRCT" => "N5",
  "CARET" => "N6", "CRRT" => "N6",
  "AMPERSAND" => "N7", "AMPS" => "N7",
  "ASTERISK" => "N8", "ASTRK" => "N8", "STAR" => "N8",
  "LEFT_PARENTHESIS" => "N9", "LPAR" => "N9", "LPRN" => "N9",
  "RIGHT_PARENTHESIS" => "N0", "RPAR" => "N0", "RPRN" => "N0",
}.freeze

# Reverse: base key -> preferred shifted alias name (for clean output).
SHIFTED_ALIAS_FOR = {
  "MINUS" => "UNDERSCORE",
  "EQUAL" => "PLUS",
  "LBKT" => "LEFT_BRACE",
  "RBKT" => "RIGHT_BRACE",
  "BSLH" => "PIPE",
  "SEMI" => "COLON",
  "SQT" => "DOUBLE_QUOTES",
  "GRAVE" => "TILDE",
  "COMMA" => "LESS_THAN",
  "DOT" => "GREATER_THAN",
  "FSLH" => "QUESTION",
  "N1" => "EXCLAMATION",
  "N2" => "AT_SIGN",
  "N3" => "HASH",
  "N4" => "DOLLAR",
  "N5" => "PERCENT",
  "N6" => "CARET",
  "N7" => "AMPERSAND",
  "N8" => "ASTERISK",
  "N9" => "LEFT_PARENTHESIS",
  "N0" => "RIGHT_PARENTHESIS",
}.freeze

# macOS uses QWERTY positions for Cmd shortcuts regardless of keyboard layout.
# Keys wrapped in LG()/RG() should NOT be translated.
CMD_MODIFIERS = %w[LG RG].freeze

def normalize(keycode)
  ALIASES.fetch(keycode, keycode)
end

def translate_keycode(keycode_str, table)
  # Function-wrapped keycodes: MOD(INNER) — handles nesting via recursion
  if keycode_str =~ /\A([A-Z][A-Z0-9_]*)\((.+)\)\z/
    func = Regexp.last_match(1)
    inner = Regexp.last_match(2)

    return keycode_str if CMD_MODIFIERS.include?(func)

    translated_inner = translate_keycode(inner, table)
    return "#{func}(#{translated_inner})"
  end

  # Shifted aliases (e.g., UNDERSCORE = LS(MINUS))
  if (base = SHIFTED_ALIASES[keycode_str])
    normalized_base = normalize(base)
    if table.key?(normalized_base)
      translated_base = table[normalized_base]
      return SHIFTED_ALIAS_FOR.fetch(translated_base, "LS(#{translated_base})")
    end
    return keycode_str
  end

  # Plain keycode: normalize for lookup, preserve original if not translatable
  normalized = normalize(keycode_str)
  table.fetch(normalized, keycode_str)
end

# Regex for a keycode token: WORD or WORD(...) with up to one level of nesting.
KEYCODE_RE = /[A-Z][A-Z0-9_]*(?:\((?:[^()]*|\([^()]*\))*\))?/

def translate_line(line, table)
  return line if line =~ /\A\s*(?:\/\/|\*|\/\*)/

  result = line.dup

  # &kp KEYCODE, &sk KEYCODE, &kt KEYCODE
  result.gsub!(/(&(?:kp|sk|kt)\s+)(#{KEYCODE_RE})/) do
    "#{Regexp.last_match(1)}#{translate_keycode(Regexp.last_match(2), table)}"
  end

  # &mt KEYCODE KEYCODE — translate both (non-translatable keys pass through)
  result.gsub!(/(&mt\s+)(#{KEYCODE_RE})(\s+)(#{KEYCODE_RE})/) do
    m = Regexp.last_match
    "#{m[1]}#{translate_keycode(m[2], table)}#{m[3]}#{translate_keycode(m[4], table)}"
  end

  # &lt LAYER KEYCODE — layer number stays, keycode translates
  result.gsub!(/(&lt\s+)(\d+)(\s+)(#{KEYCODE_RE})/) do
    m = Regexp.last_match
    "#{m[1]}#{m[2]}#{m[3]}#{translate_keycode(m[4], table)}"
  end

  result
end

def translate_file(input, direction)
  table = direction == :to_ansi ? DVORAK_TO_QWERTY : QWERTY_TO_DVORAK
  input.each_line.map { |line| translate_line(line, table) }.join
end

# --- Self-tests ---

def run_tests
  results = {pass: 0, fail: 0}

  check = lambda do |desc, actual, expected|
    if actual == expected
      results[:pass] += 1
    else
      results[:fail] += 1
      $stderr.puts "FAIL: #{desc}"
      $stderr.puts "  expected: #{expected.inspect}"
      $stderr.puts "  actual:   #{actual.inspect}"
    end
  end

  # Basic letter translation (QWERTY scancode -> what Dvorak shows)
  check["Q -> SQT",    translate_keycode("Q", QWERTY_TO_DVORAK), "SQT"]
  check["W -> COMMA",  translate_keycode("W", QWERTY_TO_DVORAK), "COMMA"]
  check["E -> DOT",    translate_keycode("E", QWERTY_TO_DVORAK), "DOT"]
  check["Z -> SEMI",   translate_keycode("Z", QWERTY_TO_DVORAK), "SEMI"]
  check["X -> Q",      translate_keycode("X", QWERTY_TO_DVORAK), "Q"]
  check["N -> B",      translate_keycode("N", QWERTY_TO_DVORAK), "B"]

  # Reverse (want this on screen -> send this scancode)
  check["SQT -> Q",    translate_keycode("SQT", DVORAK_TO_QWERTY), "Q"]
  check["COMMA -> W",  translate_keycode("COMMA", DVORAK_TO_QWERTY), "W"]
  check["SEMI -> Z",   translate_keycode("SEMI", DVORAK_TO_QWERTY), "Z"]

  # Punctuation
  check["SEMI -> S",     translate_keycode("SEMI", QWERTY_TO_DVORAK), "S"]
  check["SQT -> MINUS",  translate_keycode("SQT", QWERTY_TO_DVORAK), "MINUS"]
  check["MINUS -> LBKT", translate_keycode("MINUS", QWERTY_TO_DVORAK), "LBKT"]
  check["FSLH -> Z",     translate_keycode("FSLH", QWERTY_TO_DVORAK), "Z"]

  # Alias normalization
  check["SEMICOLON -> S",     translate_keycode("SEMICOLON", QWERTY_TO_DVORAK), "S"]
  check["APOSTROPHE -> MINUS", translate_keycode("APOSTROPHE", QWERTY_TO_DVORAK), "MINUS"]
  check["SLASH -> Z",         translate_keycode("SLASH", QWERTY_TO_DVORAK), "Z"]
  check["PERIOD -> V",        translate_keycode("PERIOD", QWERTY_TO_DVORAK), "V"]

  # Shifted keycodes LS(X)
  check["LS(Z) -> LS(SEMI)",   translate_keycode("LS(Z)", QWERTY_TO_DVORAK), "LS(SEMI)"]
  check["LS(Q) -> LS(SQT)",    translate_keycode("LS(Q)", QWERTY_TO_DVORAK), "LS(SQT)"]
  check["RS(W) -> RS(COMMA)",  translate_keycode("RS(W)", QWERTY_TO_DVORAK), "RS(COMMA)"]

  # Shifted aliases
  check["UNDERSCORE -> LEFT_BRACE",  translate_keycode("UNDERSCORE", QWERTY_TO_DVORAK), "LEFT_BRACE"]
  check["PLUS -> RIGHT_BRACE",       translate_keycode("PLUS", QWERTY_TO_DVORAK), "RIGHT_BRACE"]
  check["LEFT_BRACE -> QUESTION",    translate_keycode("LEFT_BRACE", QWERTY_TO_DVORAK), "QUESTION"]
  check["RIGHT_BRACE -> PLUS",       translate_keycode("RIGHT_BRACE", QWERTY_TO_DVORAK), "PLUS"]
  check["COLON -> LS(S)",            translate_keycode("COLON", QWERTY_TO_DVORAK), "LS(S)"]
  check["DOUBLE_QUOTES -> UNDERSCORE", translate_keycode("DOUBLE_QUOTES", QWERTY_TO_DVORAK), "UNDERSCORE"]
  check["QUESTION -> LS(Z)",         translate_keycode("QUESTION", QWERTY_TO_DVORAK), "LS(Z)"]

  # Non-translatable shifted aliases (base is number or non-remapped key)
  check["LEFT_PARENTHESIS unchanged", translate_keycode("LEFT_PARENTHESIS", QWERTY_TO_DVORAK), "LEFT_PARENTHESIS"]
  check["EXCLAMATION unchanged",      translate_keycode("EXCLAMATION", QWERTY_TO_DVORAK), "EXCLAMATION"]
  check["PIPE unchanged",             translate_keycode("PIPE", QWERTY_TO_DVORAK), "PIPE"]
  check["TILDE unchanged",            translate_keycode("TILDE", QWERTY_TO_DVORAK), "TILDE"]

  # Modifier wrapping
  check["LA(Q) -> LA(SQT)",           translate_keycode("LA(Q)", QWERTY_TO_DVORAK), "LA(SQT)"]
  check["LC(LS(Z)) -> LC(LS(SEMI))",  translate_keycode("LC(LS(Z))", QWERTY_TO_DVORAK), "LC(LS(SEMI))"]
  check["RC(W) -> RC(COMMA)",         translate_keycode("RC(W)", QWERTY_TO_DVORAK), "RC(COMMA)"]

  # Cmd modifier — NOT translated (macOS uses QWERTY positions for Cmd shortcuts)
  check["LG(Q) unchanged", translate_keycode("LG(Q)", QWERTY_TO_DVORAK), "LG(Q)"]
  check["RG(C) unchanged", translate_keycode("RG(C)", QWERTY_TO_DVORAK), "RG(C)"]
  check["LG(LS(Z)) unchanged", translate_keycode("LG(LS(Z))", QWERTY_TO_DVORAK), "LG(LS(Z))"]

  # Non-translatable keys preserved
  check["A unchanged",          translate_keycode("A", QWERTY_TO_DVORAK), "A"]
  check["M unchanged",          translate_keycode("M", QWERTY_TO_DVORAK), "M"]
  check["N1 unchanged",         translate_keycode("N1", QWERTY_TO_DVORAK), "N1"]
  check["LEFT_SHIFT unchanged", translate_keycode("LEFT_SHIFT", QWERTY_TO_DVORAK), "LEFT_SHIFT"]
  check["LEFT_ARROW unchanged", translate_keycode("LEFT_ARROW", QWERTY_TO_DVORAK), "LEFT_ARROW"]
  check["BSPC unchanged",       translate_keycode("BSPC", QWERTY_TO_DVORAK), "BSPC"]
  check["NUMBER_4 unchanged",   translate_keycode("NUMBER_4", QWERTY_TO_DVORAK), "NUMBER_4"]

  # Line translation
  check["kp line",
    translate_line("&kp Q  &kp W  &kp E", QWERTY_TO_DVORAK),
    "&kp SQT  &kp COMMA  &kp DOT"]
  check["mixed behaviors",
    translate_line("&kp TAB  &kp Q  &mo 1", QWERTY_TO_DVORAK),
    "&kp TAB  &kp SQT  &mo 1"]
  check["lt line",
    translate_line("&lt 1 Q  &lt 2 SEMI", QWERTY_TO_DVORAK),
    "&lt 1 SQT  &lt 2 S"]
  check["mt line",
    translate_line("&mt LSHFT Q", QWERTY_TO_DVORAK),
    "&mt LSHFT SQT"]
  check["sk line",
    translate_line("&sk Q", QWERTY_TO_DVORAK),
    "&sk SQT"]
  check["modifier-wrapped kp",
    translate_line("&kp LA(LEFT_ARROW)  &kp LA(Q)", QWERTY_TO_DVORAK),
    "&kp LA(LEFT_ARROW)  &kp LA(SQT)"]
  check["shifted kp",
    translate_line("&kp LS(Z)  &kp UNDERSCORE", QWERTY_TO_DVORAK),
    "&kp LS(SEMI)  &kp LEFT_BRACE"]
  check["comment preserved",
    translate_line("// |  Q  |  W  |", QWERTY_TO_DVORAK),
    "// |  Q  |  W  |"]
  check["trans and none preserved",
    translate_line("&trans  &none  &kp Q", QWERTY_TO_DVORAK),
    "&trans  &none  &kp SQT"]

  # Roundtrip: to_wysiwyg then to_ansi should restore original
  original = "&kp Q  &kp SEMI  &kp MINUS  &kp FSLH"
  wysiwyg = translate_line(original, QWERTY_TO_DVORAK)
  roundtrip = translate_line(wysiwyg, DVORAK_TO_QWERTY)
  check["roundtrip plain keys", roundtrip, original]

  original_shifted = "&kp UNDERSCORE  &kp PLUS  &kp LEFT_BRACE"
  wysiwyg_shifted = translate_line(original_shifted, QWERTY_TO_DVORAK)
  roundtrip_shifted = translate_line(wysiwyg_shifted, DVORAK_TO_QWERTY)
  check["roundtrip shifted aliases", roundtrip_shifted, original_shifted]

  original_mod = "&kp LS(Z)  &kp LA(Q)"
  wysiwyg_mod = translate_line(original_mod, QWERTY_TO_DVORAK)
  roundtrip_mod = translate_line(wysiwyg_mod, DVORAK_TO_QWERTY)
  check["roundtrip modifier-wrapped", roundtrip_mod, original_mod]

  total = results[:pass] + results[:fail]
  puts "#{total} tests: #{results[:pass]} passed, #{results[:fail]} failed"
  exit(results[:fail] > 0 ? 1 : 0)
end

# --- CLI ---

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: translate.rb [options] <keymap_file>"
  opts.on("--to-ansi", "Convert WYSIWYG -> ANSI scancodes (for flashing)") { options[:direction] = :to_ansi }
  opts.on("--to-wysiwyg", "Convert ANSI scancodes -> WYSIWYG (for reading)") { options[:direction] = :to_wysiwyg }
  opts.on("-o", "--output FILE", "Output file (default: stdout)") { |f| options[:output] = f }
  opts.on("-i", "--in-place", "Modify input file in place") { options[:in_place] = true }
  opts.on("--test", "Run self-tests") { run_tests }
  opts.on("-h", "--help", "Show help") { puts opts; exit }
end
parser.parse!

unless options[:direction]
  $stderr.puts "Error: specify --to-ansi or --to-wysiwyg"
  $stderr.puts parser
  exit 1
end

input_file = ARGV[0]
unless input_file
  $stderr.puts "Error: specify an input keymap file"
  $stderr.puts parser
  exit 1
end

input = File.read(input_file)
output = translate_file(input, options[:direction])

if options[:in_place]
  File.write(input_file, output)
elsif options[:output]
  File.write(options[:output], output)
else
  print output
end
