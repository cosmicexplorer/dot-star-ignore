fs = require 'fs'
path = require 'path'

lo = require 'lodash'
async = require 'async'

# utilities
compose = (target, funs...) ->
  target = fun target for fun in funs
  target
boolify = (res) -> if res then yes else no

getIsntDirectoryWaterfall = (f, fcb, negate) ->
  async.waterfall [
    (wcb) -> fs.stat f, wcb
    (stats, wcb) ->
      res = stats.isDirectory()
      wcb null, (if negate then res else not res)],
    (err, res) -> if err then fcb no else fcb res

# ignore file manipulation
commentRegex = /^\s*#/g
nonSpaceRegex = /[^\s]/g

class IgnoreFile
  constructor: (@name, @precedence) ->
  matches: (files, cb) ->
    matches = files.filter (f) => (path.basename f) is @name
    async.filter matches,
      # directories can't be ignore files
      getIsntDirectoryWaterfall,
      (res) => cb null, res.map (file) => {file, ignoreFileObj: @}
  toIgnorePatterns: (dir, contents) ->
    contents.split('\n')
      .filter((line) -> not line.match commentRegex)
      .filter((line) -> line.match nonSpaceRegex)
      .map (line) => new IgnorePattern
        pattern: line
        precedence: @precedence
        dir: dir

# wildcard -> regex processing
initNegateRegex = /^!/g
initRecursiveRegex = /^\//g
finDirRegex = /\/\s*$/g

ignorePatternFromIgnoreLine = (line) ->
  negated = boolify line.match initNegateRegex
  line = line.replace initNegateRegex, ''
  recursive = not line.match initRecursiveRegex
  line = line.replace initRecursiveRegex, ''
  needsDirectory = boolify line.match finDirRegex
  line = line.replace finDirRegex, ''
  # braces aren't allowed in .gitignore files, so escape
  line = line.replace /\{|\}/g, (res) -> "\\#{res}"
  reg = regexFromWildcard line
  {negated, recursive, needsDirectory, reg}

regexFromWildcard = (pattern) ->
  inBraces = no
  fin = pattern.replace(
    /((?:\\\\)*)(\\?)((?:\*|\[|\||\(|\)|\.|\+|\?|\$|\{|\}|,)+)/g,
    (res, backslashes, beforeBackslash, controlChars, offset, curPat) ->
      final = backslashes
      if beforeBackslash
        final += lo.escapeRegExp controlChars[0]
        controlChars = controlChars[1..]
      skipNext = no
      final += (for cchar, i in controlChars
        if skipNext
          skipNext = no
          continue
        afterChar = if i < controlChars.length - 1
            controlChars[i + 1]
          else null
        switch cchar
          when '*'
            if afterChar is '*'
              skipNext = yes
              '.*'
            else "[^#{path.sep}]*"
          when '['
            if afterChar is '^'
              skipNext = yes
              '[^'
            else '['
          when '{'
            braceIndex = curPat.indexOf '}', offset
            if braceIndex is -1 then lo.escapeRegExp '{'
            else
              inBraces = yes
              '('
          when ','
            if inBraces then '|' else ','
          when '}'
            if inBraces
              inBraces = no
              ')'
            else lo.escapeRegExp '}'
          else lo.escapeRegExp cchar).join ''
      final)
  "^#{fin}$"

fileDeeperThanDir = (file, dir) ->
  (path.dirname path.relative dir, file) isnt '.'

getRelativePathSequence = (dir, file) ->
  dirPaths = (path.relative dir, file).split path.sep
  dirPaths[-i..].join path.sep for _, i in dirPaths

class IgnorePattern
  constructor: ({@pattern, @precedence, @dir}) ->
    {@reg, @negated, @recursive, @needsDirectory} =
      ignorePatternFromIgnoreLine @pattern
    console.log @reg
  matches: (file, cb) ->
    f = path.basename file
    pathSeqs = getRelativePathSequence @dir, file
    switch
      when not (p.match @reg for p in pathSeqs).some(boolify) then cb no
      when (fileDeeperThanDir file, @dir) and not @recursive then cb no
      when @needsDirectory then getIsntDirectoryWaterfall file, cb, yes
      else cb yes

defaultIgnoreFiles = [new IgnoreFile '.gitignore', 0]
defaultPatterns = (dir) -> [new IgnorePattern
  pattern: '.git/'
  precedence: 0
  dir: dir]

getNewIgnoreFiles = (dir, ignoreFileObjs) -> (files, cb) ->
  files = files.map (f) -> path.join dir, f
  async.map ignoreFileObjs,
    ((ignoreFile, mcb) ->
      ignoreFile.matches files, mcb),
    (err, res) -> cb err, files, lo.flatten res

getNewPatterns = (dir) -> (files, ignoreFilesFromDir, cb) ->
  newIgnoreFiles = lo.uniq ignoreFilesFromDir, no, 'file'
  async.map newIgnoreFiles, (({file, ignoreFileObj}, mcb) ->
    fs.readFile file, (err, res) -> if err then mcb err
    else
      try
        pats = ignoreFileObj.toIgnorePatterns dir, res.toString()
        mcb null, pats
      catch err then mcb S.invalidIgnorePattern file, err),
    (err, res) -> cb err, files, lo.flatten res

getMaxOfProp = (prop, arr) ->
  max = -Infinity
  for el in arr
    if el[prop] > max then max = el[prop]
  max

applyPatterns = (invert) -> (files, patterns, cb) -> async.filter files,
  ((file, fcb) -> async.filter patterns,
    ((pat, fcb2) -> pat.matches file, fcb2),
    (pats) ->
      if pats.length is 0 then fcb yes
      else
        max = getMaxOfProp 'precedence', pats
        patsOfHighestPrecedence = pats.filter (p) -> p.precedence is max
        fcb invert isnt (lo.last patsOfHighestPrecedence).negated),
  (results) -> cb null, patterns, results

splitFilesDirectories = (patterns, nextFiles, cb) ->
  async.filter nextFiles,
    ((f, fcb) -> getIsntDirectoryWaterfall f, fcb, yes),
    (dirMatches) ->
      cb null,
        files: (lo.without nextFiles, dirMatches...)
        dirs: dirMatches
        patterns: patterns

mapToProperty = (prop, l) -> l.map (it) -> it[prop]

recurseIgnore = ({invert, ignoreFileObjs}, dir, cb) ->
  (err, opts) ->
    {
      files: matchFiles
      dirs: matchDirs
      patterns
    } = opts
    if err then cb err
    else switch matchDirs.length
      when 0 then cb null, {files: matchFiles, dirs: []}
      else async.map matchDirs,
        ((matchedDir, mcb) ->
          getTracked matchedDir, {invert, ignoreFileObjs, patterns},
            (err, res) -> if err then mcb err else mcb null, {matchedDir, res}),
        (err, results) ->
          if err then cb err
          else
            cleanedDirs = mapToProperty 'matchedDir', results
            flattened = mapToProperty 'res', results
            cleanedDirs = cleanedDirs.concat mapToProperty 'dirs', flattened
            cleanedFiles = mapToProperty 'files', flattened
            trackedFiles = lo.uniq lo.flatten matchFiles.concat cleanedFiles
            dirsWithFiles = (lo.uniq lo.flatten cleanedDirs).filter (dir) ->
              trackedFiles.some (f) -> f.startsWith dir
            cb null,
              files: trackedFiles
              dirs: dirsWithFiles

optionalOpts = (fun) -> (arg, opts, cb) ->
  if typeof opts is 'function' then fun arg, null, opts else fun arg, opts, cb

getTracked = optionalOpts (dir, opts = {}, cb) ->
  {
    invert = no                         # immutable
    ignoreFileObjs = defaultIgnoreFiles # immutable
    patterns = defaultPatterns dir      # added to on each recursion
  } = opts
  async.waterfall [
    ((wcb) -> fs.readdir dir, wcb)
    getNewIgnoreFiles dir, ignoreFileObjs
    getNewPatterns dir
    # append to old patterns
    (files, ignorePatternsFromDir, wcb) ->
      patterns = patterns.concat ignorePatternsFromDir
      wcb null, files, patterns
    applyPatterns invert
    splitFilesDirectories],
    recurseIgnore {invert, ignoreFileObjs}, dir, cb

module.exports = {
  getTracked
  IgnoreFile
  getRelativePathSequence
  IgnorePattern
  regexFromWildcard
  defaultIgnoreFiles
  defaultPatterns
}
