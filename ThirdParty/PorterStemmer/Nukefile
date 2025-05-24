;; source files
;(set @c_files     (filelist "^objc/.*.c$"))
(set @m_files     (filelist "^objc/.*.m$"))
(set @nu_files 	  (filelist "^nu/.*nu$"))

(set SYSTEM ((NSString stringWithShellCommand:"uname") chomp))
(case SYSTEM
      ("Darwin"
               (set @arch (list "x86_64" ))
               (set @cflags "-g -std=gnu99 -fobjc-gc -DDARWIN")
               (set @ldflags  "-framework Foundation"))
      ("Linux"
              (set @arch (list "i386"))
              (set gnustep_flags ((NSString stringWithShellCommand:"gnustep-config --objc-flags") chomp))
              (set gnustep_libs ((NSString stringWithShellCommand:"gnustep-config --base-libs") chomp))
              (set @cflags "-g -std=gnu99 -DLINUX -I/usr/local/include #{gnustep_flags}")
              (set @ldflags "#{gnustep_libs}"))
      (else nil))

;; framework description
(set @framework "PorterStemmer")
(set @framework_identifier "nu.programming.PorterStemmer")
(set @framework_creator_code "????")

(ifDarwin
         (set @public_headers (filelist "^objc/.*\.h$")))

(compilation-tasks)
(framework-tasks)

(task "default" => "framework")

(task "doc" is (SH "nudoc"))

