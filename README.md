.*ignore
=======

A module to traverse directories of git repositories according to `.gitignore` (and other specified) files. Written because I couldn't figure out how to use any of the other options.

# Usage
```javascript
var DSIgnore = require('dot-star-ignore');
DSIgnore('.', function (err, files) {
  if (err) { console.error(err); }
  else {
    console.log("files tracked by git in folder '.': ");
    console.log(files.join('\n'));
  }
});
```

# API
```javascript
function DSIgnore(dir, [options,] callback) {
```

- `dir`: root directory to perform traversal on. `DSIgnore` follows symlinks, so ensure your directory tree is not cyclical.
- `options` is an object with parameters:
  - `invert`: if truthy, returns files (or function, if `filter` is on) *matching* the ignored patterns, instead of ignoring the patterns.
  - `ignoreFiles`: array of `IgnoreFile` objects, which are specified [below](#ignorefile).
    - defaults to `[{name: '.gitignore', precedence: 0}]`.
  - `patterns`: array of `IgnorePattern` objects, which are specified [below](#ignorepattern).
    - defaults to `[{pattern: '.git/', precedence: 0, positive: true}]`.
- `callback(err, files)`: bubbles up all `fs` errors, returns matched files.

# Objects

## IgnoreFile

```javascript
{
  name, // string
  precedence // integer
}
```

- `name`: exact text matching ignore file; `.gitignore`, `.npmignore`, etc. Matches filenames, not their paths (so `../.gitignore` isn't allowed).
- `precedence`: positive integer specifying which files take precedence over others. If two IgnoreFile objects have the same precedence, the resulting behavior is undefined.


## IgnorePattern

```javascript
{
  pattern, // string
  precedence, // integer
  negated // boolean
}
```

- `pattern`: glob pattern, taken relative to the directory of the file the pattern was found in
- `precedence`: as in `IgnoreFile`
- `negated`: whether the pattern had a `!` at front in the ignore file
