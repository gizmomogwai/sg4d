module main;

import argparse : CLI;
import args : Args;
import viewed : viewedMain;

mixin CLI!(Args).main!(args => args.viewedMain);
