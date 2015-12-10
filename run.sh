#!/bin/sh
# Copyright (c) 2015 Cédric Bosdonnat <cedric@bosdonnat.fr>
# 
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

grab_data ()
{
    wget -O $WORKDIR/data.zip http://donnees.roulez-eco.fr/opendata/jour
    unzip $WORKDIR/data.zip -d $WORKDIR
}

create_osm ()
{
    data=$1
    osmfile=$2
    fuel=$3
    filtered=$WORKDIR/filtered
    extract=$WORKDIR/extract
    echo '<pdv_liste>' >$filtered
    xmllint --xpath "//prix[@nom='$fuel']/parent::*" $data >>$filtered
    echo '</pdv_liste>' >>$filtered

    xmllint --xpath "//pdv/@id|//@latitude|//@longitude|//ouverture/@debut|//ouverture/@fin|//ouverture/@saufjour|//prix[@nom='$fuel']/@maj|//prix[@nom='$fuel']/@valeur" $filtered >$extract
    sed 's/^ //;s/ id/\n id/g;s/[a-z]\+=//g;s/" "/|/g;s/ \?"//g' -i $extract

    case "$fuel" in

        Gazole)
            f="diesel"
            ;;
        SP95)
            f="octane_95"
            ;;
        SP98)
            f="octane_98"
            ;;
        GPLc)
            f="lgp"
            ;;
        E85)
            f="e85"
            ;;
        E10)
            f="e10"
            ;;
    esac

    awk -F'|' -v d=100000 -v dprix=1000 \
       'BEGIN{print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osm version=\"0.5\">"}
        {
            split("Lundi;Mardi;Mercredi;Jeudi;Vendredi;Samedi;Dimanche;End", ordered_days, ";")

            days_convert["Lundi"] = "Mo"
            days_convert["Mardi"] = "Tu"
            days_convert["Mercredi"] = "We"
            days_convert["Jeudi"] = "Th"
            days_convert["Vendredi"] = "Fr"
            days_convert["Samedi"] = "Sa"
            days_convert["Dimanche"] = "Su"

            if ($4 == $5 && length($6) == 0)
            {
                opening = "24/7"
            }
            else
            {
                split($6, closed, ";")
                for (item in closed)
                    closed_days[closed[item]] = 1
                closed_days["End"] = 1

                start = ""
                last_opened = ""
                open_days = ""
                for (id in ordered_days)
                {
                    day = ordered_days[id]
                    if (day in closed_days)
                    {
                        range = ""
                        if (length(start) != 0)
                            range = start
                        if (length(last_opened) != 0 && last_opened != start)
                            range = range  "-" last_opened
                        if (length(range) != 0)
                            open_days = open_days range ","
                        last_opened = ""
                        start = ""
                    }
                    else
                    {
                        if (length(start) == 0)
                            start = days_convert[day]
                        last_opened = days_convert[day]
                    }
                }
                if (length(open_days) == 0)
                    open_days = "Mo-Su,"
                opening = open_days "PH " substr($4,0,5) "-" substr($5,0,5)

                for (id in closed)
                    delete closed[id]
                for (id in closed_days)
                    delete closed_days[id]
            }
            date = substr($7, 0, index($7, "T") - 1)

            print "<node id=\"" $1 "\" visible=\"true\" lat=\"" ($2/d) "\" lon=\"" ($3/d) "\">\n"
            print "  <tag k=\"name\" v=\"'"$fuel"' " ($8/dprix) "€\"/>\n"
            print "  <tag k=\"description\" v=\"" ($8/dprix) "€ (" date ")\"/>\n"
            print "  <tag k=\"opening_hours\" v=\"" opening "\"/>\n"
            print "  <tag k=\"amenity\" v=\"fuel\"/>\n"
            print "  <tag k=\"fuel:'"$f"'\" v=\"yes\"/>\n"
            print "  <tag k=\"user_defined\" v=\"'"$fuel"'\"/>\n"
            print "  <tag k=\"source\" v=\"prix-carburant.economie.gouv.fr\"/>\n"
            print "</node>\n"
        }
        END{print "</osm>"}' OFS=''  <$extract >$osmfile
}

create_obf ()
{
    create_obf_in=$1
    create_obf_out=$2
    mapcreator=$PWD/OsmAndMapCreator-main
    batch=$mapcreator/osm2obf.xml

    # Download OsmandMapCreator if needed
    if ! test -e "$mapcreator"; then
        mkdir -p "$mapcreator"
        wget http://download.osmand.net/latest-night-build/OsmAndMapCreator-main.zip
        unzip OsmAndMapCreator-main.zip -d $mapcreator
    fi


    cat >$batch <<EOF
<?xml version="1.0" encoding="utf-8"?>
<batch_process>
    <process_attributes
        mapZooms=""
        renderingTypesFile=""
        zoomWaySmoothness=""
        osmDbDialect="sqlite"
        mapDbDialect="sqlite"/>
    <process
        directory_for_osm_files="$create_obf_in"
        directory_for_index_files="$create_obf_out"
        directory_for_generation="$create_obf_out"
        skipExistingIndexesAt=""
        indexPOI="true"
        indexRouting="false"
        indexMap="false"
        indexTransport="false"
        indexAddress="false">
    </process>
</batch_process>
EOF

  cd "$mapcreator"
  java -Djava.util.logging.config.file=logging.properties -Xms256M -Xmx2560M \
       -cp "./OsmAndMapCreator.jar:./lib/OsmAnd-core.jar:./lib/*.jar" \
       net.osmand.data.index.IndexBatchCreator osm2obf.xml
  cd $OLDPWD
}

WORKDIR=$PWD/tmp
if ! test -e $WORKDIR; then
    mkdir $WORKDIR
fi

osmdir=$PWD/osm
obfdir=$PWD/obf

if ! test -e $osmdir; then
    mkdir $osmdir
fi

if ! test -e $obfdir; then
    mkdir $obfdir
fi

grab_data

data=$(ls -1 $WORKDIR/*.xml)

sed -n '/<prix/{s/\ *<prix nom="\([^"]\+\).*$/\1/;p}' "$data" | sort | uniq | while read -r gas; do
    create_osm "$data" "$osmdir/$gas.osm" $gas
done

create_obf "$osmdir" "$obfdir"
rm $obfdir/*.gen.log

for f in $(ls -1 $obfdir*.obf); do
    newname=$(echo "$f" | sed "s/_2//")
    mv $f $newname
done

rm -rf $WORKDIR
rm -rf "$osmdir"
