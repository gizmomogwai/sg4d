/++
 + License: MIT
 + Copyright: Copyright (c) 2017, Christian Koestlin
 + Authors: Christian Köstlin
 +/

import unit_threaded;

// dfmt off
mixin runTestsMain!(
    "deepface",
    "viewed",
    "viewed.expression",
    "viewed.tags"
);
// dfmt on
