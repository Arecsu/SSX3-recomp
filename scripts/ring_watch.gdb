# Watch the world stream manager's ring pointers (M+0x60 read, M+0x64 write)
# from the moment its first request starts. Usage:
#   gdb -batch -x scripts/ring_watch.gdb --args build-linux/ssx3_recomp   (cwd = project root)
set pagination off
set confirm off
set $b = 0x100000000000
handle SIGSEGV SIGUSR1 SIGUSR2 SIGPIPE nostop noprint pass
set $armed = 0
break sub_00177990
commands
  silent
  set $M = *(unsigned int*)&g_esi
  set $req = *(unsigned int*)($b+$M+0x70)
  if $armed == 0 && $req != 0 && *(unsigned int*)($b+$req+0x14) == 0x7461647c
    set $armed = 1
    printf "ARMED M=%x\n", $M
    watch -l *(unsigned int*)($b+$M+0x60)
    commands
      silent
      printf "RD t=%d val=%x ", $_thread, *(unsigned int*)($b+$M+0x60)
      info symbol $pc
      continue
    end
    watch -l *(unsigned int*)($b+$M+0x64)
    commands
      silent
      printf "WR t=%d val=%x ", $_thread, *(unsigned int*)($b+$M+0x64)
      info symbol $pc
      continue
    end
  end
  continue
end
run
