import Foundation
import OSLog

/// The Linux commands LinPad Duo adds, installed into /usr/local/bin each time Linux has
/// booted, so the stock LinPad system image works without being rebuilt.
///
/// They talk to the app through files under /tmp/linpad-duo, which the app reads (and,
/// for `ask`, writes) directly in the guest's file system. The app can only change files
/// the guest created: the fakefs keeps each file's metadata itself, so the scripts create
/// every file the app writes into.
enum DuoGuestTools {
    static let directory = "/tmp/linpad-duo"
    static let jobsDirectory = directory + "/jobs"
    static let askDirectory = directory + "/ask"
    /// Bumped when a script changes, so an installed copy is replaced.
    static let version = "1"
    private static let logger = Logger(subsystem: "DesktopKit", category: "DuoGuestTools")

    static let notifyPhone = #"""
        #!/bin/sh
        # LinPad Duo v\#(version): show a long Linux job on the iPhone, in LinPad's tent board,
        # the Dynamic Island and the Lock Screen (Settings › iPhone Duo › Live Activities).
        #
        #   id=$(notify-phone start "Building the app")    start a job; prints its id
        #   notify-phone update "$id" 40 "Linking"           progress 0-100, optional detail
        #   notify-phone done "$id" "Built in 2 minutes"     finished (detail optional)
        #   notify-phone fail "$id" "Tests failed"           finished with an error
        #   notify-phone run "Building the app" -- make -j4  run a command as a job
        dir=\#(jobsDirectory)
        mkdir -p "$dir" || exit 1
        clean() { printf '%s' "$1" | tr '\n\r=' '  -' | cut -c1-200; }
        field() { [ -f "$dir/$1.job" ] && sed -n "s/^$2=//p" "$dir/$1.job"; }
        write() { # id state progress title detail
            title=$(clean "$4"); [ -n "$title" ] || title=$(field "$1" title)
            started=$(field "$1" started); [ -n "$started" ] || started=$(date +%s)
            tmp="$dir/.$1.$$"
            {
                echo "title=${title:-Linux job}"
                echo "state=$2"
                echo "progress=$3"
                echo "detail=$(clean "$5")"
                echo "started=$started"
                echo "updated=$(date +%s)"
            } > "$tmp" && mv -f "$tmp" "$dir/$1.job"
        }
        newid() { echo "$(date +%s)-$$"; }
        usage() { sed -n '2,10s/^# \{0,1\}//p' "$0" >&2; exit 2; }
        case "$1" in
            start) [ -n "$2" ] || usage; id=$(newid); write "$id" running "" "$2" "$3"; echo "$id" ;;
            update) [ -n "$2" ] || usage; write "$2" running "$3" "" "$4" ;;
            done) [ -n "$2" ] || usage; write "$2" done 100 "" "$3" ;;
            fail) [ -n "$2" ] || usage; write "$2" failed "$(field "$2" progress)" "" "$3" ;;
            run)
                [ -n "$2" ] || usage
                title=$2; shift 2; [ "$1" = "--" ] && shift
                [ $# -gt 0 ] || usage
                id=$(newid); write "$id" running "" "$title" "$*"
                "$@"; code=$?
                if [ $code -eq 0 ]; then write "$id" done 100 "" ""; else write "$id" failed "" "" "Exit code $code"; fi
                exit $code ;;
            *) usage ;;
        esac
        """#

    static let ask = #"""
        #!/bin/sh
        # LinPad Duo v\#(version): answer a question with Apple's on-device model, offline.
        #   ask "How do I list open ports?"
        #   cat notes.txt | ask "Summarise this"
        # Needs Apple Intelligence, and Settings › iPhone Duo › On-device AI in LinPad.
        dir=\#(askDirectory)
        mkdir -p "$dir" || exit 1
        q="$*"
        if [ ! -t 0 ]; then
            input=$(head -c 24000)
            q="$q

        $input"
        fi
        [ -n "$(printf '%s' "$q" | tr -d ' \n')" ] || { sed -n '3,4s/^# \{0,1\}//p' "$0" >&2; exit 2; }
        id="$(date +%s)-$$"
        : > "$dir/$id.answer"
        printf '%s' "$q" > "$dir/.$id.tmp" && mv -f "$dir/.$id.tmp" "$dir/$id.question"
        trap 'rm -f "$dir/$id.answer" "$dir/$id.question"; exit 130' INT TERM
        [ -t 2 ] && printf 'Thinking…\r' >&2
        i=0
        until grep -q '^__LINPAD_END__$' "$dir/$id.answer" 2>/dev/null; do
            sleep 0.3; i=$((i + 1))
            if [ $i -gt 600 ]; then
                echo "ask: no answer from the phone. Is LinPad in front, and Settings › iPhone Duo › On-device AI on?" >&2
                rm -f "$dir/$id.answer" "$dir/$id.question"; exit 1
            fi
        done
        [ -t 2 ] && printf '           \r' >&2
        status=$(sed -n 's/^__LINPAD_STATUS__ //p' "$dir/$id.answer")
        if [ "$status" = ok ]; then
            sed '/^__LINPAD_END__$/d; /^__LINPAD_STATUS__ /d' "$dir/$id.answer"
        else
            sed '/^__LINPAD_END__$/d; /^__LINPAD_STATUS__ /d' "$dir/$id.answer" >&2
        fi
        rm -f "$dir/$id.answer" "$dir/$id.question"
        [ "$status" = ok ]
        """#

    /// Writes both commands unless the installed copies are this version. Runs after boot.
    static func install(on host: any LinuxHost) async {
        let marker = "LinPad Duo v\(version):"
        let check = await host.run("[ \"$(grep -l '\(marker)' /usr/local/bin/notify-phone /usr/local/bin/ask 2>/dev/null | wc -l)\" -eq 2 ]")
        guard !check.succeeded else { return }
        do {
            _ = await host.run("mkdir -p /usr/local/bin \(directory) \(jobsDirectory) \(askDirectory)")
            try await host.writeFile("/usr/local/bin/notify-phone", data: Data(notifyPhone.utf8))
            try await host.writeFile("/usr/local/bin/ask", data: Data(ask.utf8))
            _ = await host.run("chmod 755 /usr/local/bin/notify-phone /usr/local/bin/ask")
            logger.info("installed notify-phone and ask")
        } catch {
            logger.error("could not install the Duo commands: \(error.localizedDescription, privacy: .public)")
        }
    }
}
