module main;

import viewed;
import args : Args;
import argparse : CLI;

mixin CLI!(Args).main!(args => args.viewedMain);
