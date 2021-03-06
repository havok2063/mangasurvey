Function mlmedian,InpVector

; Program median_drl
; Returns the median value of an input vector

; Find indices of sorted values
indexx=sort(InpVector)

; Make new sorted vector
SortedVec=InpVector[indexx]

; What is size of vector?
vecsize=size(SortedVec)

; Choose the middle element if vecsize is odd
if (vecsize[1] mod 2 eq 1) then begin
  retval=SortedVec[vecsize[1]/2]
; Otherwise return mean of middle two elements
endif else begin
  retval=(SortedVec[vecsize[1]/2-1]+SortedVec[vecsize[1]/2])/2.
endelse

return,retval
end
