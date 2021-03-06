#!/bin/sh

NAME="$( basename "${0}"; printf a )"; NAME="${NAME%?a}"

show_help() {
  printf %s\\n "SYNOPSIS" >&2
  printf %s\\n "  ${NAME} <JOB> [<arg> ...]" >&2


  printf %s\\n "" "JOBS" >&2
  <"${0}" awk '
    /^my_make/ { run = 1; }
    /^\}/ { run = 0; }
    run && /^    in|^    ;;/ {
      sub(/^ *in /, "  ", $0);
      sub(/^ *;; /, "  ", $0);
      sub(/\) *#/, "\t", $0);
      sub(/\).*/, "", $0);
      print $0;
    }
  ' >&2

  printf %s\\n '' "EXAMPLE" \
    "  ${NAME} archive-by-rss UCWPKJM4CT6ES2BrUz9wbELw ./downloaded ./metadata" \
    "  ${NAME} add-to-archive ./downloaded ./metadata ./subtitles >/dev/null" \
    "  ${NAME} add-missing-subs ./downloaded ./metadata ./subtitles" \
    "  ${NAME} add-to-archive ./downloaded ./metadata ./subtitles >./archive.txt" \
    "  ${NAME} download-playlist-list https://www.youtube.com/user/HeiJinZhengZhi >./playlist.json" \
  >&2
  exit 1
}

NEWLINE='
'

# In case we have to change to youtube-dlc due to bugs
ytdl() {
  # youtube-dlc "$@"
  youtube-dl "$@"
}

#run: sh % help
# run: sh % download-playlist-list https://www.youtube.com/user/HeiJinZhengZhi
# run: sh % archive-by-rss UCWPKJM4CT6ES2BrUz9wbELw ./new ./archive.txt
# run: sh % add-to-archive ./downloaded ./metadata ./subtitles
# run: sh % add-missing-subs ./downloaded ./metadata ./subtitles
# run: sh % autosub SocMustDie.webm ./test

my_make() {
  case "${1}"
    ############################################################################
    # Main maintenance actions
    in archive-by-rss) # <channel-id> <interim-directory> <metadata-directory>
      errln '' 'Step 1: Downloading metadata and subtitles (by RSS)'
      [ -d "${3}" ] || die FATAL 1 "Arg three '${3}' must be a directory"
      [ -d "${4}" ] || die FATAL 1 "Arg four '${4}' must be a directory"

      rss="https://www.youtube.com/feeds/videos.xml?channel_id=${2}"
      errln "Curling channel RSS feed '${rss}'..."

      for id in $(
        curl -L "${rss}" \
          | awk '$0 ~ "<link.*href=\"https://www.youtube.com/watch" {
            gsub(".*href=\"https://www\\.youtube\\.com/watch\\?v=", "");
            gsub("\"/>$", "");
            print $0;
          }'
      ); do
        [ "${#id}" != '11' ] && die FATAL 1 "Parse error of RSS feed: '${id}'"
        if [ ! -e "${4}/${id}.info.json" ]; then
          ytdl --write-info-json --skip-download --continue --ignore-errors \
            --no-overwites --no-post-overwrites \
            --sub-lang en --write-auto-sub \
            --output "${3}/%(id)s" \
            "https://www.youtube.com/watch?v=${id}"
        fi
      done

    ;; archive-by-channel) # <channel-url> <interim-directory> <archive-file>
      errln '' 'Step 1: Download metadata and subtitles (by youtube-dl channel)'
      [ -d "${3}" ] || die FATAL 1 "Arg three '${3}' must be a directory"
      [ -w "${4}" ] || die FATAL 1 "Arg four '${4}' must be a writable file"
      ytdl --write-info-json --skip-download --continue --ignore-errors \
        --no-overwites --no-post-overwrites \
        --write-auto-sub --sub-lang en \
        --download-archive "${4}" \
        --output "${3}/%(id)s" \
        "${2}"



    ;; add-to-archive) # <interim-directory> <metadata-directory> <subtitle-directory>
      errln '' 'Step 2 or 4: Adding downloaded files to archive'
      [ -d "${2}" ] || die FATAL 1 "Arg two '${2}' must be a directory"
      [ -d "${3}" ] || die FATAL 1 "Arg three '${3}' must be a directory"
      [ -d "${4}" ] || die FATAL 1 "Arg four '${4}' must be a directory"
      interim="${2}"
      metadata="${3}"
      subtitle="${4}"

      #errln "Before adding, there are $( wc -l "${4}" ) files in the archive"

      count='0'
      to_add=''
      move_files_and_count_moves() {
        count="$(( count + 1 ))"
        name="${1##*/}"

        case "${1}"
          in *.json)   printf %s\\n "${name%.info.json}"
                       mv "${interim}/${name}" "${metadata}/${name}" || exit "$?"
          ;; *.vtt)    mv "${interim}/${name}" "${subtitle}/${name}" || exit "$?"
          #  This is from 'add-missing-subtitle' job
          ;; *.audio)  rm "${interim}/${name}"
          ;; *)  die DEV 1 "File '${1}' had an unexpected file extension"
        esac
      }
      for_each_file_in_dir "${2}" move_files_and_count_moves
      #errln "Processed ${count} files"
      #errln "${count} files moved to '${3}' and '${4}'"
      #errln "" "There are $( wc -l "${4}" ) files in the archive"


    ;; add-missing-subs) # <interim-directory> <metadata-directory> <subtitle-directory> <skip>
      errln '' 'Step 3: Adding any missing subtitles'
      [ -d "${2}" ] || die FATAL 1 "Arg two '${2}' must be a directory"
      [ -d "${3}" ] || die FATAL 1 "Arg three '${3}' must be a directory"
      [ -d "${4}" ] || die FATAL 1 "Arg four '${4}' must be a directory"
      interim="${2}"
      metadata="${3}"
      subtitle="${4}"
      skipfile="${5}"

      #check_is_empty() {
      #  printf %s\\n "${1}"
      #  errln "Because there are files in the interim directory,"
      #  errln "we are assuming '${NAME} add-missing-subs' ended prematurely."
      #  errln "Please empty the interim directory '${interim}'"
      #  exit 1
      #}
      #for_each_file_in_dir "${interim}" check_is_empty

      transcribe_missing_subs() {
        filepath="${1##*/}"
        id="${filepath%.info.json}"
        [ "${id}" != "${filepath}" ] || die FATAL 1 \
          "Cannot handle file extension for '${1}'" \
          "Expected a '<id>.info.json' file from youtube-dl"

        if   [ ! -f "${subtitle}/${id}.en.vtt" ] \
          && ! grep -qF -- "${id}" "${skipfile}"
        then
          errln "===== Subtitling ${id} ====="
          [ ! -f "${interim}/${id}.audio" ] \
            && youtube-dl --format bestaudio \
              --output "${interim}/%(id)s.audio" \
              "https://youtube.com/watch?v=${id}"

          # Return so that we do not run `my_make autosub` which will
          # exit if the file does not exist
          if   [ -f "${interim}/${id}.audio" ] \
            && [ ! -f "${interim}/${id}.en.vtt" ]
          then
            my_make autosub "${interim}/${id}.audio" "${interim}"
          fi

          # Add to ${interim} so that we can Ctrl-C halfway
        fi
        return 0
      }
      for_each_file_in_dir "${metadata}" transcribe_missing_subs



    ############################################################################
    # Utility functions

    ;; autosub) # <file> <output-dir>
      docker images "${name}" --format "{{.Repository}}" | grep -F "autosub" \
        || die FATAL 1 "'autosub' docker image not built yet" \
          "See https://github.com/abhirooptalasila/AutoSub"
      [ -r "${2}" ] || die FATAL 1 "Arg two '${2}' must be a readable file"
      [ -d "${3}" ] || die FATAL 1 "Arg three '${3}' must be a directory"
      inp_path="$( realpath -P "${2}"; printf a )"; inp_path="${inp_path%?a}"
      out_dir="$(  realpath -P "${3}"; printf a )"; out_dir="${out_dir%?a}"
      filename="${2##*/}"
      ext="${filename##*.}"
      stem="${filename%".${ext}"}"

      printf '' >"${out_dir}/${stem}.en.vtt"
      docker run --rm \
        -v "${inp_path}:/app/${stem}.en.${ext}:ro" \
        -v "${out_dir}:/output" \
        autosub:0.9.3 --format vtt --file "/app/${stem}.en.${ext}"

    ;; download-playlist-list) # <channel-url>
        dump="$( ytdl -4 --ignore-errors --dump-json --flat-playlist \
          "${2}/playlists"
        )" || exit "$?"
        printf %s\\n "${dump}" | jq --slurp 'sort_by(.title)'

    ;; list-stems) # <directory>
      [ -d "${2}" ] || die FATAL 1 "Arg two '${2}' must be a directory"

      print_stem() {
        filename="${1##*/}"
        printf %s\\n "${filename%%.*}"
      }
      for_each_file_in_dir "${2}" print_stem

    ;; help|*) show_help
  esac
}

for_each_file_in_dir() {
  fe_dir="${1}"
  fe_cmd="${2}"
  shift 2
  for fe_file in "${fe_dir}"/* "${fe_dir}"/.[!.]* "${fe_dir}"/..?*; do
    [ -e "${fe_file}" ] || continue
    "${fe_cmd}" "${fe_file}" "$@" || exit "$?"
  done
}

errln() { printf %s\\n "$@" >&2; }
die() { printf %s "${1}: " >&2; shift 1; printf %s\\n "$@" >&2; exit "${1}"; }

my_make "$@"
