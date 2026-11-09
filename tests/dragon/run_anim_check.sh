#!/bin/zsh
# 体素巨龙动画自动检查：固定 1/60s 步长跑完整演示序列（约 62 秒动画），检查
# IK 足底误差 / 支撑相滑步 / 骨长 / 反关节 / 关节单步跳变 / 穿地 / 左右翼对称 / 状态覆盖。
# 用法：tests/dragon/run_anim_check.sh   （需要 Maker CLI：MAKER 指向 taptap-maker 命令）
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MAKER=${MAKER:-taptap-maker}
OUT=$ROOT/.tmp/dragon_check; rm -rf "$OUT"; mkdir -p "$OUT"
cp "$ROOT/tests/dragon/anim_check.lua" "$ROOT/scripts/_dragon_vtest.lua"
eval $MAKER preview validate --target-dir "\"$ROOT\"" --mode validate --entry dragon_main.lua \
  --validate-test _dragon_vtest.lua --validate-frames 600 --validate-timeout 200 \
  --validate-spike-threshold 5000 --nosound --output-dir "\"$OUT\"" --json > "$OUT/cli.json" 2>&1
rm -f "$ROOT/scripts/_dragon_vtest.lua"
grep -h "DragonCheck" "$OUT"/*/runtime.log | sed 's/.*\[DragonCheck\]/[DragonCheck]/; s/\\n"}//; s/"}//' | sort -u
python3 -c "
import json
d=json.loads(open('$OUT/cli.json').read().strip().split('\n')[-1])
print('test:', d['report'].get('test_result'), d['report'].get('test_assertions'))"
