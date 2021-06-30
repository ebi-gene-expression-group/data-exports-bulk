#!/usr/bin/python3

"""
This script adds to an Expression Atlas' EB-eye XML dump tissue and disease information retrieved 
from condensed sdrf files. 
Author: Robert Petryszak (info@datasome.co.uk)
"""

from xml.dom import minidom
from re import sub, match, IGNORECASE
import os
import sys
import time

class EBEyeDumpEnrichmentError(Exception):
    pass

def createAppendElement(doc, parentElem, elemName, elemText, elemAttributeTuples=[]):
    """
    1. Create xml elemName
    2. Populate it with attributes in elemAttributeTuples, 
    3. Append to elemName a child text node elemText
    4. Append elemName as a child of parentElem
    """
    el = doc.createElement(elemName)
    if (elemText):
        el.appendChild(doc.createTextNode(elemText))
    for attrVal in elemAttributeTuples:
        el.setAttribute(attrVal[0], attrVal[1])
    parentElem.appendChild(el)

def retrieveSampleAnnotationsFromCondensedSdrfFile(condensedSdrfFilePath):
    """
    Retrieve from condensedSdrfFilePath disease and tissue annotations (including cross-references 
    to ontology terms) and store them in diseases, tissues and crossRefs sets respectively.

    >>> retrieveSampleAnnotationsFromCondensedSdrfFile('!')
    Traceback (most recent call last):
       ...
    EBEyeDumpEnrichmentError: ERROR: ! doesn't exist
    """
    if os.path.exists(condensedSdrfFilePath):
        with open(condensedSdrfFilePath, 'r') as condensedSdrfFile:
            condensedSdrfStr = condensedSdrfFile.read()
            return retrieveSampleAnnotationsFromCondensedSdrf(condensedSdrfStr)
    else:
        raise EBEyeDumpEnrichmentError("ERROR: " + condensedSdrfFilePath + " doesn't exist")
"""
Retrieve from condensedSdrfStr disease and tissue annotations (including cross-references 
to ontology terms) and store them in diseases, tissues and crossRefs sets respectively.
"""
def retrieveSampleAnnotationsFromCondensedSdrf(condensedSdrfStr):
    """
    >>> (diseases, tissues, crossRefs) = retrieveSampleAnnotationsFromCondensedSdrf("")
    >>> len(diseases)
    0
    >>> (diseases, tissues, crossRefs) = retrieveSampleAnnotationsFromCondensedSdrf("E-MTAB-2770\\t\\trun_5637.2\\tfactor\\tcell line\t5637\thttp://www.ebi.ac.uk/efo/EFO_0002096")
    >>> len(diseases) + len(tissues) + len(crossRefs)
    0
    >>> (diseases, tissues, crossRefs) = retrieveSampleAnnotationsFromCondensedSdrf("E-MTAB-2770\\t\\trun_5637.2\\tfactor\\tdisease\\tbladder carcinoma\\thttp://www.ebi.ac.uk/efo/EFO_0000292")
    >>> "bladder carcinoma" in diseases
    True
    >>> "EFO_0000292" in crossRefs
    True
    >>> tissues
    set()
    >>> (diseases, tissues, crossRefs) = retrieveSampleAnnotationsFromCondensedSdrf("E-MTAB-513\\t\\tERR030881\\tfactor\\torganism part\\tadrenal\\thttp://purl.obolibrary.org/obo/UBERON_0002369")
    >>> "adrenal" in tissues
    True
    >>> "UBERON_0002369" in crossRefs
    True
    >>> diseases
    set()
    """
    diseases, tissues, crossRefs  = (set([]), set([]), set([]))
    for row in condensedSdrfStr.split("\n"):
        arr = row.strip().split("\t")
        if len(arr) > 4 and arr[3] == "factor":
            if arr[4].lower() == "organism part":
                tissues.add(arr[5].strip())
                if len(arr) > 6:
                    crossRefs.add(arr[6].split("/")[-1].strip())             
            elif arr[4].lower() == "disease":
                diseases.add(arr[5].strip())
                if len(arr) > 6:
                    crossRefs.add(arr[6].split("/")[-1].strip())
    return (diseases, tissues, crossRefs)

def addSampleAnnotationsToEntry(doc, entry, diseases, tissues, crossRefs):
    """
    Add annotations in diseases, tissues, crossRefs to entry
    >>> doc = minidom.Document()
    >>> entry = doc.createElement('entry')
    >>> addSampleAnnotationsToEntry(doc, entry, {'bladder carcinoma'}, {}, {'EFO_0000292'})
    >>> entry.getElementsByTagName("additional_fields").length
    1
    >>> entry.getElementsByTagName("cross_references").length
    1
    >>> entry.getElementsByTagName("additional_fields").item(0).firstChild.toprettyxml(indent="").strip() == '<field name="disease">bladder carcinoma</field>'
    True
    >>> entry.getElementsByTagName("cross_references").item(0).firstChild.toprettyxml(indent="").strip() == '<ref dbName="efo" dbkey="EFO_0000292"/>'
    True
    >>> entry = doc.createElement('entry')
    >>> addSampleAnnotationsToEntry(doc, entry, {}, {'adrenal'}, {})
    >>> entry.getElementsByTagName("additional_fields").item(0).firstChild.toprettyxml(indent="").strip() == '<field name="tissue">adrenal</field>'
    True
    """
    if diseases or tissues:
        if len(entry.getElementsByTagName("additional_fields")) == 0:
            createAppendElement(doc, entry, "additional_fields","")
        additionalFields = entry.getElementsByTagName("additional_fields")[0]
        if len(entry.getElementsByTagName("cross_references")) == 0:
            createAppendElement(doc, entry, "cross_references","")
        crossReferences = entry.getElementsByTagName("cross_references")[0]
        for tissue in tissues:
            createAppendElement(doc, additionalFields, 'field', tissue, [('name','tissue')])
        for disease in diseases:
            createAppendElement(doc, additionalFields, 'field', disease, [('name','disease')])
        for ontologyTerm in crossRefs:
            ontologyName = ontologyTerm.split("_")[0].lower()
            createAppendElement(doc, crossReferences, 'ref', None, [('dbkey', ontologyTerm),('dbName', ontologyName)])

condensedSDRFRootDir = None
if __name__ == "__main__":
    # Capture call arguments
    if len(sys.argv) < 2:
        print('Call argument needed, e.g. : ')
        print(sys.argv[0] + ' ebeye_baseline_experiments.xml /path/to/condensed/sdrf')
        print('or:')
        print(sys.argv[0] + ' test')
        sys.exit()
xmlFilePath = sys.argv[1]
if len(sys.argv) > 2:
    condensedSDRFRootDir = sys.argv[2]

if xmlFilePath == "test":
    import doctest
    doctest.testmod(verbose=False) 
else:
    t0 = time.time()
    doc = minidom.parse(xmlFilePath)
    print("Parsed %s successfully in %d seconds" % (xmlFilePath, round(time.time() - t0)))

    entries = doc.getElementsByTagName('entry')
    t0 = time.time()
    recCnt = 0
    for entry in entries:
        accession = entry.attributes['id'].value
        for expAcc in os.listdir(condensedSDRFRootDir):
            if expAcc == accession:
                condensedSdrfFilePath = os.path.join(condensedSDRFRootDir, expAcc, "%s.condensed-sdrf.tsv" % expAcc)
                (diseases, tissues, crossRefs) = retrieveSampleAnnotationsFromCondensedSdrfFile(condensedSdrfFilePath)
                addSampleAnnotationsToEntry(doc, entry, diseases, tissues, crossRefs)
        recCnt += 1
        if recCnt % 200 == 0:
            print("Processed %d entries - %d seconds so far" % (recCnt, round(time.time() - t0)))
    print("Processed %d %s entries successfully in %d seconds" % (len(entries), xmlFilePath, round(time.time() - t0)))
    xmlStr = doc.toprettyxml(indent="  ")
    xmlStr = os.linesep.join([s for s in xmlStr.splitlines() if s.strip()])
    with open("%s.enriched" % xmlFilePath, "w") as f:
        f.write(xmlStr)
