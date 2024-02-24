# R3

## Building the computer

```lua
loadfile("/path/to/spaghetti/loader.lua")("/path/to/this/repo", function()
	require("r3").build(20, 6) -- core count, RAM row count order (0 = 1 row, 1 = 2 rows, 2 = 4 rows, ...)
end)
```

## Generating individual components

### core

```lua
loadfile("/path/to/spaghetti/loader.lua")("/path/to/this/repo", function()
	require("spaghetti.runner").run({
		module = require("r3.core"),
		output = "/path/to/this/repo/r3/core/generated.lua",
	})
end)
```

### rread

```lua
loadfile("/path/to/spaghetti/loader.lua")("/path/to/this/repo", function()
	require("spaghetti.runner").run({
		module = require("r3.rread"),
		output = "/path/to/this/repo/r3/rread/generated.lua",
	})
end)
```
