set $b = 0x100000000000
set $tab = *(unsigned int*)($b+0x39E884)
printf "table %x count %d\n", $tab, *(int*)($b+0x39E880)
set $i = 0
while $i < 32
  set $e = $b + $tab + $i*20
  if *(unsigned int*)$e != 0
    printf "fd %d handle %x cached %x size %x base %x +10 %x\n", $i, *(unsigned int*)$e, *(unsigned int*)($e+4), *(unsigned int*)($e+8), *(unsigned int*)($e+12), *(unsigned int*)($e+16)
  end
  set $i = $i + 1
end
