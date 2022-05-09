//
//  VT100DCSParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"
#import "iTermParser.h"
#import "CVector.h"

NS_ASSUME_NONNULL_BEGIN

@protocol VT100DCSParserHook<NSObject>

@property(nonatomic, readonly) NSString *hookDescription;

// Return YES if it should unhook.
- (BOOL)handleInput:(iTermParserContext *)context
support8BitControlCharacters:(BOOL)support8BitControlCharacters
              token:(VT100Token *)result;

@end

typedef NS_ENUM(NSInteger, DcsTermcapTerminfoRequestName) {
    kDcsTermcapTerminfoRequestUnrecognizedName,
    kDcsTermcapTerminfoRequestTerminalName,
    kDcsTermcapTerminfoRequestiTerm2ProfileName,
    kDcsTermcapTerminfoRequestTerminfoName,
    kDcsTermcapTerminfoRequestNumberOfColors,
    kDcsTermcapTerminfoRequestNumberOfColors2,
    kDcsTermcapTerminfoRequestDirectColorWidth,

    // key_backspace               kbs       kb     backspace key
    kDcsTermcapTerminfoRequestKey_kb,
    // key_dc                      kdch1     kD     delete-character key
    kDcsTermcapTerminfoRequestKey_kD,
    // key_down                    kcud1     kd     down-arrow key
    kDcsTermcapTerminfoRequestKey_kd,
    // key_end                     kend      @7     end key
    kDcsTermcapTerminfoRequestKey_at_7,
    // key_enter                   kent      @8     enter/send key
    kDcsTermcapTerminfoRequestKey_at_8,
    // key_f1                      kf1       k1     F1 function key
    kDcsTermcapTerminfoRequestKey_k1,
    // key_f2                      kf2       k2     F2 function key
    kDcsTermcapTerminfoRequestKey_k2,
    // key_f3                      kf3       k3     F3 function key
    kDcsTermcapTerminfoRequestKey_k3,
    // key_f4                      kf4       k4     F4 function key
    kDcsTermcapTerminfoRequestKey_k4,
    // key_f5                      kf5       k5     F5 function key
    kDcsTermcapTerminfoRequestKey_k5,
    // key_f6                      kf6       k6     F6 function key
    kDcsTermcapTerminfoRequestKey_k6,
    // key_f7                      kf7       k7     F7 function key
    kDcsTermcapTerminfoRequestKey_k7,
    // key_f8                      kf8       k8     F8 function key
    kDcsTermcapTerminfoRequestKey_k8,
    // key_f9                      kf9       k9     F9 function key
    kDcsTermcapTerminfoRequestKey_k9,
    // key_f10                     kf10      k;     F10 function key
    kDcsTermcapTerminfoRequestKey_k_semi,
    // key_f11                     kf11      F1     F11 function key
    kDcsTermcapTerminfoRequestKey_F1,
    // key_f12                     kf12      F2     F12 function key
    kDcsTermcapTerminfoRequestKey_F2,
    // key_f13                     kf13      F3     F13 function key
    kDcsTermcapTerminfoRequestKey_F3,
    // key_f14                     kf14      F4     F14 function key
    kDcsTermcapTerminfoRequestKey_F4,
    // key_f15                     kf15      F5     F15 function key
    kDcsTermcapTerminfoRequestKey_F5,
    // key_f16                     kf16      F6     F16 function key
    kDcsTermcapTerminfoRequestKey_F6,
    // key_f17                     kf17      F7     F17 function key
    kDcsTermcapTerminfoRequestKey_F7,
    // key_f18                     kf18      F8     F18 function key
    kDcsTermcapTerminfoRequestKey_F8,
    // key_f19                     kf19      F9     F19 function key
    kDcsTermcapTerminfoRequestKey_F9,
    // key_home                    khome     kh     home key
    kDcsTermcapTerminfoRequestKey_kh,
    // key_left                    kcub1     kl     left-arrow key
    kDcsTermcapTerminfoRequestKey_kl,
    // key_npage                   knp       kN     next-page key
    kDcsTermcapTerminfoRequestKey_kN,
    // key_ppage                   kpp       kP     previous-page key
    kDcsTermcapTerminfoRequestKey_kP,
    // key_right                   kcuf1     kr     right-arrow key
    kDcsTermcapTerminfoRequestKey_kr,
    // key_sdc                     kDC       *4     shifted delete-character key
    kDcsTermcapTerminfoRequestKey_star_4,
    // key_send                    kEND      *7     shifted end key
    kDcsTermcapTerminfoRequestKey_star_7,
    // key_shome                   kHOM      #2     shifted home key
    kDcsTermcapTerminfoRequestKey_pound_2,
    // key_sleft                   kLFT      #4     shifted left-arrow key
    kDcsTermcapTerminfoRequestKey_pound_4,
    // key_sright                  kRIT      %i     shifted right-arrow key
    kDcsTermcapTerminfoRequestKey_pct_i,
    // key_up                      kcuu1     ku     up-arrow key
    kDcsTermcapTerminfoRequestKey_ku,

    // Unsupported:
    // key_a1                      ka1       K1     upper left of keypad
    // key_a3                      ka3       K3     upper right of
    // key_b2                      kb2       K2     center of keypad
    // key_beg                     kbeg      @1     begin key
    // key_btab                    kcbt      kB     back-tab key
    // key_c1                      kc1       K4     lower left of keypad
    // key_c3                      kc3       K5     lower right of keypad
    // key_cancel                  kcan      @2     cancel key
    // key_catab                   ktbc      ka     clear-all-tabs key
    // key_clear                   kclr      kC     clear-screen or erase key
    // key_close                   kclo      @3     close key
    // key_command                 kcmd      @4     command key
    // key_copy                    kcpy      @5     copy key
    // key_create                  kcrt      @6     create key
    // key_ctab                    kctab     kt     clear-tab key
    // key_dl                      kdl1      kL     delete-line key
    // key_eic                     krmir     kM     sent by rmir or smir in insert mode
    // key_eol                     kel       kE     clear-to-end-of-line key
    // key_eos                     ked       kS     clear-to-end-of-screen key
    // key_exit                    kext      @9     exit key
    // key_f0                      kf0       k0     F0 function key
    // key_f20                     kf20      FA     F20 function key
    // key_f21                     kf21      FB     F21 function key
    // key_f22                     kf22      FC     F22 function key
    // key_f23                     kf23      FD     F23 function key
    // key_f24                     kf24      FE     F24 function key
    // key_f25                     kf25      FF     F25 function key
    // key_f26                     kf26      FG     F26 function key
    // key_f27                     kf27      FH     F27 function key
    // key_f28                     kf28      FI     F28 function key
    // key_f29                     kf29      FJ     F29 function key
    // key_f30                     kf30      FK     F30 function key
    // key_f31                     kf31      FL     F31 function key
    // key_f32                     kf32      FM     F32 function key
    // key_f33                     kf33      FN     F33 function key
    // key_f34                     kf34      FO     F34 function key
    // key_f35                     kf35      FP     F35 function key
    // key_f36                     kf36      FQ     F36 function key
    // key_f37                     kf37      FR     F37 function key
    // key_f38                     kf38      FS     F38 function key
    // key_f39                     kf39      FT     F39 function key
    // key_f40                     kf40      FU     F40 function key
    // key_f41                     kf41      FV     F41 function key
    // key_f42                     kf42      FW     F42 function key
    // key_f43                     kf43      FX     F43 function key
    // key_f44                     kf44      FY     F44 function key
    // key_f45                     kf45      FZ     F45 function key
    // key_f46                     kf46      Fa     F46 function key
    // key_f47                     kf47      Fb     F47 function key
    // key_f48                     kf48      Fc     F48 function key
    // key_f49                     kf49      Fd     F49 function key
    // key_f50                     kf50      Fe     F50 function key
    // key_f51                     kf51      Ff     F51 function key
    // key_f52                     kf52      Fg     F52 function key
    // key_f53                     kf53      Fh     F53 function key
    // key_f54                     kf54      Fi     F54 function key
    // key_f55                     kf55      Fj     F55 function key
    // key_f56                     kf56      Fk     F56 function key
    // key_f57                     kf57      Fl     F57 function key
    // key_f58                     kf58      Fm     F58 function key
    // key_f59                     kf59      Fn     F59 function key
    // key_f60                     kf60      Fo     F60 function key
    // key_f61                     kf61      Fp     F61 function key
    // key_f62                     kf62      Fq     F62 function key
    // key_f63                     kf63      Fr     F63 function key
    // key_find                    kfnd      @0     find key
    // key_help                    khlp      %1     help key
    // key_ic                      kich1     kI     insert-character key
    // key_il                      kil1      kA     insert-line key
    // key_ll                      kll       kH     lower-left key (home down)
    // key_mark                    kmrk      %2     mark key
    // key_message                 kmsg      %3     message key
    // key_move                    kmov      %4     move key
    // key_next                    knxt      %5     next key
    // key_open                    kopn      %6     open key
    // key_options                 kopt      %7     options key
    // key_previous                kprv      %8     previous key
    // key_print                   kprt      %9     print key
    // key_redo                    krdo      %0     redo key
    // key_reference               kref      &1     reference key
    // key_refresh                 krfr      &2     refresh key
    // key_replace                 krpl      &3     replace key
    // key_restart                 krst      &4     restart key
    // key_resume                  kres      &5     resume key
    // key_save                    ksav      &6     save key
    // key_sbeg                    kBEG      &9     shifted begin key
    // key_scancel                 kCAN      &0     shifted cancel key
    // key_scommand                kCMD      *1     shifted command key
    // key_scopy                   kCPY      *2     shifted copy key
    // key_screate                 kCRT      *3     shifted create key
    // key_sdl                     kDL       *5     shifted delete-line key
    // key_select                  kslt      *6     select key
    // key_seol                    kEOL      *8     shifted clear-to- end-of-line key
    // key_sexit                   kEXT      *9     shifted exit key
    // key_sf                      kind      kF     scroll-forward key
    // key_sfind                   kFND      *0     shifted find key
    // key_shelp                   kHLP      #1     shifted help key
    // key_sic                     kIC       #3     shifted insert-character key
    // key_smessage                kMSG      %a     shifted message key
    // key_smove                   kMOV      %b     shifted move key
    // key_snext                   kNXT      %c     shifted next key
    // key_soptions                kOPT      %d     shifted options key
    // key_sprevious               kPRV      %e     shifted previous key
    // key_sprint                  kPRT      %f     shifted print key
    // key_sr                      kri       kR     scroll-backward key
    // key_sredo                   kRDO      %g     shifted redo key
    // key_sreplace                kRPL      %h     shifted replace key
    // key_srsume                  kRES      %j     shifted resume key
    // key_ssave                   kSAV      !1     shifted save key
    // key_ssuspend                kSPD      !2     shifted suspend key
    // key_stab                    khts      kT     set-tab key
    // key_sundo                   kUND      !3     shifted undo key
    // key_suspend                 kspd      &7     suspend key
    // key_undo                    kund      &8     undo key
};

NSString *VT100DCSNameForTerminfoRequest(DcsTermcapTerminfoRequestName code);

NS_INLINE BOOL isDCS(unsigned char *code, int len, BOOL support8BitControlCharacters) {
    if (support8BitControlCharacters && len >= 1 && code[0] == VT100CC_C1_DCS) {
        return YES;
    }
    return (len >= 2 && code[0] == VT100CC_ESC && code[1] == 'P');
}

typedef NS_ENUM(NSInteger, VT100DCSState) {
    // Initial state
    kVT100DCSStateEntry,

    // Intermediate bytes, usually zero or one punctuation marks.
    kVT100DCSStateIntermediate,

    // Semicolon-delimited numeric parameters
    kVT100DCSStateParam,

    // Waiting for terminator but failure is guaranteed.
    kVT100DCSStateIgnore,

    // Finished.
    kVT100DCSStateGround,

    // ESC after ground state.
    kVT100DCSStateEscape,

    // After ESC while in DCS.
    kVT100DCSStateDCSEscape,

    // Reading final byte or bytes.
    kVT100DCSStatePassthrough
};

@interface VT100DCSParser : NSObject

// Indicates if a hook is present. All input should be sent to the DCS Parser
// while hooked.
@property(nonatomic, readonly) BOOL isHooked;

// For debug logging; nil if no hook.
@property(nonatomic, readonly) NSString *hookDescription;

// Uniquely identifies this object so the main thread can avoid unhooking the wrong session.
@property(nonatomic, readonly) NSString *uniqueID;

+ (NSDictionary *)termcapTerminfoNameDictionary;  // string name -> DcsTermcapTerminfoRequestName
+ (NSDictionary *)termcapTerminfoInverseNameDictionary;  // DcsTermcapTerminfoRequestName -> string name

- (void)decodeFromContext:(iTermParserContext *)context
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState;

// Reset to ground state, unhooking if needed.
- (void)reset;

- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelTmuxRecoveryMode;

@end

// This is exposed for testing.
@interface VT100DCSParser (Testing)

@property(nonatomic, readonly) VT100DCSState state;
@property(nonatomic, readonly) NSArray *parameters;
@property(nonatomic, readonly) NSString *privateMarkers;
@property(nonatomic, readonly) NSString *intermediateString;
@property(nonatomic, readonly) NSString *data;

@end

NS_ASSUME_NONNULL_END

