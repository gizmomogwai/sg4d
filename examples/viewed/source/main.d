module main;

import viewed : viewedMain;
import args : Args;
import argparse : CLI;

mixin CLI!(Args).main!(args => args.viewedMain);
