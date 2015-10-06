fs = require 'fs'
path = require 'path'

lo = require 'lodash'
async = require 'async'

negateRegex = /^!/g
nonRecursiveRegex = /^!?\//g
negateOrNonRecursiveRegex = /^(!|\/)\/?/g
commentRegex = /^#/g
directoryRegex = /\/$/g

getIsntDirectoryWaterfall = (f) -> [
  (wcb) -> fs.stat f, wcb
  (stats, wcb) -> wcb null, not stats.isDirectory()]

class IgnoreFile
  constructor: (@name, @precedence) ->
  matches: (files, cb) ->
    # lambda used so the index which is the second arg to map is unused
    matches = files.map((f) -> path.basename f).filter (f) -> f is @name
    async.filter matches,
      # directories can't be ignore files
      ((f, fcb) -> async.waterfall (getIsntDirectoryWaterfall f), fcb),
      (err, res) -> if err then cb err else cb null, res.map (file) ->
        {file, ignoreFileObj: @}
  toIgnorePatterns: (dir, contents) ->
    contents.split('\n').map((line) -> line.trim())
      .filter((line) -> not line.match commentRegex)
      .map (line) => new IgnorePattern
        pattern: (line.replace negateOrNonRecursiveRegex, "")
        precedence: @precedence
        negated: (line.match negateRegex)
        dir: dir
        recursive: (not line.match nonRecursiveRegex),
        needsDirectory: (line.match directoryRegex)

regexFromIgnore = (pattern, flags) ->
  new RegExp pattern.split('').map((c) -> switch c
    when '*' then '.*'
    when '[', ']' then c
    else lo.escapeRegExp c).join(''), flags

fileDeeperThanDir = (file, dir) ->
  (path.dirname path.relative dir, file) isnt '.'

class IgnorePattern
  constructor: ({@pattern, @precedence, @negated, @dir, @recursive,
    @needsDirectory}) ->
    @reg = regexFromIgnore (path.join @dir, @pattern), 'g'
  matches: (file, cb) -> switch
    when not file.match @reg then cb null, no
    when fileDeeperThanDir file, @dir and not @recursive then cb null, no
    when @needsDirectory then fs.stat file, (err, stats) ->
      if err then cb err else cb null, stats.isDirectory()
    else cb null, yes

defaultIgnoreFiles = [new IgnoreFile '.gitignore', 0]
defaultPatterns = (dir) -> [new IgnorePattern
  pattern: '.git'
  precedence: 0
  negated: no
  dir: dir
  recursive: no
  needsDirectory: yes]

optionalOpts = (fun) -> (arg, opts, cb) ->
  if typeof opts is 'function' then fun arg, null, opts else fun arg, opts, cb

cloneOpts = ({invert, ignoreFileObjs, patterns}) ->
  {invert, ignoreFileObjs, patterns}

currySecond = (args..., fn) -> (fnArgs...) ->
  fn fnArgs[0], args..., fnArgs[1..]...

getNewIgnoreFiles = (ignoreFileObjs) -> (files, cb) -> async.map ignoreFileObjs,
  ((ignoreFile, mcb) -> ignoreFile.matches files, mcb),
  currySecond files, cb

getNewPatterns = (dir) -> (files, ignoreFilesFromDir, cb) ->
  console.log arguments
  newIgnoreFiles = lo.uniq ignoreFilesFromDir, no, 'file'
  async.map newIgnoreFiles, (({file, ignoreFileObj}, mcb) ->
    fs.readFile file, (err, res) -> if err then mcb err
    else
      pats = ignoreFileObj.toIgnorePatterns dir, res.toString()
      mcb null, pats),
    currySecond files, cb

applyPatterns = (files, patterns, cb) -> async.filter files,
  ((file, fcb) -> async.filter patterns,
    ((pat, fcb2) -> pat.matches file, fcb2),
    (err, pats) -> if err then fcb err
    else
      max = lo.max pats, 'precedence'
      patsOfHighestPrecedence = pats.filter (p) -> p.precedence is max
      fcb null, invert is (lo.last patsOfHighestPrecedence).negated),
  currySecond patterns, cb

splitFilesDirectories = (patterns, nextFiles, cb) -> async.filter nextFiles,
  ((f, fcb) -> async.waterfall [fs.stat, (s, wcb2) -> s.isDirectory()], fcb),
  (err, dirMatches) -> if err then wcb err
  else cb null, (lo.without nextFiles, dirMatches...), dirMatches, patterns

mapToProperty = (prop, l) -> l.map (it) -> it[prop]

recurseIgnore = ({invert, ignoreFileObjs}, cb) ->
  (err, matchFiles, matchDirs, patterns) ->
    if err then cb err
    else switch matchDirs.length
      when 0 then cb null, matchFiles
      else async.map matchDirs,
        ((matchedDir, mcb) ->
          DoIgnore matchedDir, {invert, ignoreFileObjs, patterns}, (err, res) ->
            if err then mcb err else mcb null, {matchedDir, res}),
        (err, results) ->
          cleaned = results.filter ({matchedDir, res}) -> res.length > 0
          if matchFiles.length is cleaned.length is 0 then cb null, []
          else
            cleanedDirs = mapToProperty 'matchedDir', cleaned
            cleanedFiles = mapToProperty 'res', cleaned
            cb null, lo.uniq matchFiles.concat files, cleanedDirs, cleanedFiles

DoIgnore = optionalOpts (dir, opts = {}, cb) ->
  {
    invert = no                         # immutable
    ignoreFileObjs = defaultIgnoreFiles # immutable
    patterns = defaultPatterns dir      # added to on each recursion
  } = opts
  async.waterfall [
    ((wcb) -> fs.readdir dir, wcb)
    getNewIgnoreFiles ignoreFileObjs
    getNewPatterns dir
    # append to old patterns
    (files, ignorePatternsFromDir, wcb) ->
      patterns = patterns.concat ignorePatternsFromDir
      wcb null, files, patterns
    applyPatterns
    splitFilesDirectories],
    recurseIgnore {invert, ignoreFileObjs}, cb
