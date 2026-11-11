local _, ns = ...

-- English is the base language: a missing key falls back to itself.
ns.L = setmetatable({}, { __index = function(_, key) return key end })
