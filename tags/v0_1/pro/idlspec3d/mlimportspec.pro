;+
; function mlimportspec
;
; Import RSS-format data output from the Phase 0 pipeline
;
; Returns 0 if everything is ok, returns an error code if there was a problem.
;
; Author:
;   David R. Law (Dunlap Institute; drlaw@di.utoronto.ca)
;   First written: 11/20/2012
;   Last modified: 01/21/2013
;
; REVISION HISTORY:
;   v1: 20-Nov-2012  D. Law
;       First written.
;   v1.1: 12-Dec-2012 D. Law
;       Working in flux calibration and b/r combination
;   v1.3: 21-Jan-2013 D. Law
;       Tweaked logging, format revisions
;   v1.4: 01-Feb-2013 D. Law
;       Major revisions for sky subtraction, flux calibration
;-

function mlimportspec,wave,redx,obsparam,slitmap,bmap,spec,xinbundle,yinbundle,fstat,filepath,flavor, quick=quick,doall=doall

; Status starts off OK
status=0

ifusize=mlgetbundlesize(redx.ifuname)
nwave=(size(wave))[1]

; Assign information from bundlemap to vectors

; Bundlemap was required to be in order, with fiber fnum=1 on line 1
; (true for serpentine layout)
for j=0,ifusize-1 do begin
  xinbundle[j]=bmap[j].xpmm
  yinbundle[j]=bmap[j].ypmm
  fstat[j]=bmap[j].gbu
endfor

; Find appropriate lines in the slitmap
sentry=slitmap[where(slitmap.ifuname eq redx.ifuname)]
; If an incorrect number of lines found, fail and exit
if ((size(sentry))[1] ne ifusize) then begin
  splog,strcompress('Error in slitmap: expected '+string(ifusize)+' entries, found '+string((size(sentry))[1]))
  status=-130L
  mlquitmanga3d,status
endif

; Figure out how fnum maps from bundle map to slit map
assignorder=intarr(ifusize)
for j=0,ifusize-1 do assignorder[j]=where(sentry.fnum eq j+1)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; If flavor=sos, just do a simple read/combine without worrying
; about keywords, flux calibration, etc.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

if flavor eq 'sos' then begin

  ; Figure out input science filenames in SOS format
  b1scifile=strcompress('sci-'+redx.plate+'-b1-'+redx.expnum+'.fits')
  r1scifile=strcompress('sci-'+redx.plate+'-r1-'+redx.expnum+'.fits')

  ; Figure out blue wset file
  b1wsetfile=file_search(strcompress(filepath+'wset-'+redx.mjd+'-'+redx.plate+'*-b1.fits',/remove_all))
  ; If wset file not found, quit
  if (size(b1wsetfile))[0] eq 0 then begin
    splog,'ERROR: Cannot find b1 wset file'
    mlquitmanga3d,-131L
  endif
  ; If more than one wset file, use the first
  if (size(b1wsetfile))[1] ne 1 then b1wsetfile=b1wsetfile[0]

  ; Figure out red wset file
  r1wsetfile=file_search(strcompress(filepath+'wset-'+redx.mjd+'-'+redx.plate+'*-r1.fits',/remove_all))
  ; If wset file not found, quit
  if (size(r1wsetfile))[0] eq 0 then begin
    splog,'ERROR: Cannot find r1 wset file'
    mlquitmanga3d,-131L
  endif
  ; If more than one wset file, use the first
  if (size(r1wsetfile))[1] ne 1 then r1wsetfile=r1wsetfile[0]

  splog,'flavor=sos reduction set- assuming SOS inputs.'
  splog,'Skipping flux calibration and doing quick extraction and combination'
  splog,strcompress('Data path: '+filepath)
  splog,'Reading data from files:'
  splog,b1scifile
  splog,r1scifile
  splog,'Read wavelength info from files:'
  splog,b1wsetfile
  splog,r1wsetfile

  ; Read all data from files
  b1sci=readfits(filepath+b1scifile)
  b1wset=mrdfits(b1wsetfile,1); Array of legendre coefficients
  r1sci=readfits(filepath+r1scifile)
  r1wset=mrdfits(r1wsetfile,1); Array of legendre coefficients

  ; Convert from legendre coefficient to CCD wavelength solution
  traceset2xy,b1wset,dummy,b1loglam; Convert from coefficients to log wavelengths
  b1lam=10.^b1loglam; Array of wavelengths for each fiber
  traceset2xy,r1wset,dummy2,r1loglam; Convert from coefficients to log wavelengths
  r1lam=10.^r1loglam; Array of wavelengths for each fiber

; Note that BOSS routine rebin_spectrum changes units of spectrum,
; while interpol does not.  Therefore if flux units were erg/s/cm2/Ang
; originally, they still will be after running interpol.  They will
; not after running rebin_spectrum

  tempspecb1=fltarr(nwave)
  tempspecr1=fltarr(nwave)
  for j=0,ifusize-1 do begin
    tempspecb1=interpol(b1sci[*,sentry[assignorder[j]].fiberid-1],b1lam[*,sentry[assignorder[j]].fiberid-1],wave)
    tempspecr1=interpol(r1sci[*,sentry[assignorder[j]].fiberid-1],r1lam[*,sentry[assignorder[j]].fiberid-1],wave)

  ; Quick version just adds blue and red
  spec[*,j]=tempspecb1+tempspecr1
  endfor
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; If flavor='full' but the /quick keyword is set, use the spFrame
; files, but do a simple combination akin to the SOS reductions.
;
; Does not do sky subtraction or flux calibration.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

if ((flavor eq 'full')and(keyword_set(quick))) then begin
  ; Quick reduction that doesn't do flux calibration

  ; Define filenames, b+r for spFrame and spSFrame
  ; Indicate whether spec 1 or 2
  fileb1=strcompress(filepath+'spFrame-b1-'+redx.expnum+'.fits.gz')
  filer1=strcompress(filepath+'spFrame-r1-'+redx.expnum+'.fits.gz')
  Sfileb1=strcompress(filepath+'spSFrame-b1-'+redx.expnum+'.fits.gz')
  Sfiler1=strcompress(filepath+'spSFrame-r1-'+redx.expnum+'.fits.gz')

  splog,'flavor=full reduction set- assuming FULL inputs.'
  splog,'/quick keyword set: skipping flux calibration'

  ; Sky subtraction on by default
  doskysub=1

  ; Is there an spSFrame?  If so, sky subtraction already done
  if (file_test(Sfileb1)) then doskysub=0

  ; If necessary, do sky subtraction
  if (doskysub) then begin
    splog,'No sky subtracted file found- doing sky subtraction now.'
    status=mlskysubtract(fileb1,obsparam,slitmap,'b1')
    status=mlskysubtract(filer1,obsparam,slitmap,'r1')
  endif else splog,'Sky subtracted file already found- skipping sky subtraction step.'

  ; Read all data from files
  b1sci=mrdfits(Sfileb1,0)
  b1wset=mrdfits(Sfileb1,3); Array of legendre coefficients
  r1sci=mrdfits(Sfiler1,0)
  r1wset=mrdfits(Sfiler1,3); Array of legendre coefficients

  ; Convert from legendre coefficient to CCD wavelength solution
  traceset2xy,b1wset,dummy,b1loglam; Convert from coefficients to log wavelengths
  b1lam=10.^b1loglam; Array of wavelengths for each fiber
  traceset2xy,r1wset,dummy2,r1loglam; Convert from coefficients to log wavelengths
  r1lam=10.^r1loglam; Array of wavelengths for each fiber

  ; Note that BOSS routine rebin_spectrum changes units of spectrum,
  ; while interpol does not.  Therefore if flux units were erg/s/cm2/Ang
  ; originally, they still will be after running interpol.  They will
  ; not after running rebin_spectrum

  tempspecb1=fltarr(nwave)
  tempspecr1=fltarr(nwave)

  for j=0,ifusize-1 do begin
    tempspecb1=interpol(b1sci[*,sentry[assignorder[j]].fiberid-1],b1lam[*,sentry[assignorder[j]].fiberid-1],wave)
    tempspecr1=interpol(r1sci[*,sentry[assignorder[j]].fiberid-1],r1lam[*,sentry[assignorder[j]].fiberid-1],wave)

    ; Quick version just adds blue and red
    spec[*,j]=tempspecb1+tempspecr1
  endfor

endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; If flavor=full and the /quick keyword is NOT set, do a full reduction that reads
; from spFrame files produced by main BOSS pipeline.
; Look for spSFrame (sky subtracted) and spCFrame (calibrated).  If
; not found, do those steps.
;
; This would use BOSS routines spframe_read.pro and spflux_v5.pro,
; but we've got to reimplement all of this to handle the fact that 
; we've got quite different rules and are using a slitmap .slm
; file in addition to the standard BOSS plPlugMapM file.  Farm this
; off into the subroutine mlfluxcal.pro as it will be a long
; and complicated process.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
if ((flavor eq 'full')and(not(keyword_set(quick)))) then begin

  splog,'flavor=full reduction set- assuming FULL inputs.'
  splog,strcompress('Data path: '+filepath)

  ; Define filenames, b+r for spFrame and spSFrame
  ; Just a single name for spCFrame and spFFrame (b+r combined)
  ; Indicate whether spec 1 or 2
  fileb1=strcompress(filepath+'spFrame-b1-'+redx.expnum+'.fits.gz')
  filer1=strcompress(filepath+'spFrame-r1-'+redx.expnum+'.fits.gz')
  Sfileb1=strcompress(filepath+'spSFrame-b1-'+redx.expnum+'.fits.gz')
  Sfiler1=strcompress(filepath+'spSFrame-r1-'+redx.expnum+'.fits.gz')
  Cfile1=strcompress(filepath+'spCFrame-'+redx.expnum+'.fits.gz')
  Ffile1=strcompress(filepath+'spFFrame-'+redx.expnum+'.fits.gz')

  ; Sky subtraction, flux calibration, and flux correction all on by default
  doskysub=1
  dofluxcal=1
  dofluxcor=1

  ; Look to see what kind of files exist:
  ; Is there an spSFrame?  If so, sky subtraction already done
  if (file_test(Sfileb1)) then doskysub=0
  ; Is there an spCFrame?  If so, flux calibration already done
  if (file_test(Cfile1)) then dofluxcal=0
  ; Is there an spFFrame?  If so, flux adjustment already done
  if (file_test(Ffile1)) then dofluxcor=0

  ; Switch: if /doall is set, do all steps regardless of what was found
  if (keyword_set(doall)) then begin
    doskysub=1
    dofluxcal=1
    dofluxcor=1
  endif

  ; If necessary, do sky subtraction
  if (doskysub) then begin
    splog,'No sky subtracted file found- doing sky subtraction now.'
    status=mlskysubtract(fileb1,obsparam,slitmap,'b1')
    status=mlskysubtract(filer1,obsparam,slitmap,'r1')
  endif else splog,'Sky subtracted file already found- skipping sky subtraction step.'

  ; If necessary, do flux calibration
  if (dofluxcal) then begin
    splog,'No flux calibrated file found- doing flux calibration now.'
    status=mlfluxcal(Sfileb1,Sfiler1,obsparam,slitmap,wave)
  endif else splog,'Flux calibrated file already found- skipping flux calibration step.'

  ; If necessary, do flux correction
  if (dofluxcor) then begin
    splog,'No flux corrected file found- doing flux correction now.'
    status=mlfluxcor_placeholder(Cfile1)
  endif else splog,'Flux corrected file already found- skipping flux correction step.'

  ; In all cases, do the extraction of lines of interest
  ; Read data from spFFrame
  finalspec=mrdfits(Ffile1,0)
  finallogwave=mrdfits(Ffile1,7)
  finalwave=10.^finallogwave

  ; Extract lines of interest for chosen IFU
  splog,'Extracting data for chosen IFU'
  ; Be stupid and interpolate the spectra to the common wavelength grid
  ; Need to do something SMARTER...
  for j=0,ifusize-1 do begin
      ;spec[*,j]=interpol(finalspec[*,sentry[assignorder[j]].fiberid-1],finalwave,wave)
      spec[*,j]=finalspec[*,sentry[assignorder[j]].fiberid-1]
  endfor

 endif


return,status
end
