{ fetchFromGitHub }:
# 唯一的上游版本锁定点。CLI、Flutter bridge、GUI 和插件资源都从这里取源码。
# 升级请运行 pkgs/update.py，不要手动只改其中一处。
let
  rev = "903169997b61a399e102f979abca8342af0e3ec3";
in
{
  inherit rev;
  version = "2.0.0-preview.14";
  src = fetchFromGitHub {
    owner = "AAswordman";
    repo = "Operit2";
    inherit rev;
    hash = "sha256-sn0Ew69o1tVATOGcvYGZZkPnmLC4OLBTAcHtvxqk9hc=";
  };
}
