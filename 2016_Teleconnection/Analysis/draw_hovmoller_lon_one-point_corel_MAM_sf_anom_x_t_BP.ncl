;*************************************************************
;Aim: Draw hovmoller diagram (time vs. longitude) of one-point lagged correlation of daily anomalous stream function deviations from zonal mean 
;Mission:
;
;   1. Read data from daily U & V datasets
;   2. Post-post process to deserved results
;   3. Draw the hovmoller diagram
;                       He Shan
;                       2016-05-27
;
;*************************************************************

load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/shea_util.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/diagnostics_cam.ncl"

begin

;================================================
;Variables List:
;	var1--------------uwnd
;	var2--------------vwnd
;================================================

;datas
    in_path1 = "~/data/observation/NCEP_DOE/daily/uwnd/"
    in_path2 = "~/data/observation/NCEP_DOE/daily/vwnd/"

;time
    mS     = 3
    mE     = 5
    season = "MAM"
    maxlag = 10

;Base point
    lat = 25
    lon = 60

;Region
    latN = 35
    latS = 20
    lonL = -60
    lonR = 180

;data
    out_path = "~/hes/One_Belt_One_Road/Fig/"
    out_name = "hovmoller_lon_one-point_corel_"+season+"_sf_anom_x_t_BP_"+lat+"N"+lon+"E"

    text1 = (/2.,6.,10.,14.,18./)
    text2 = (/"-8","-4","0","+4","+8"/)

; ==============================================================
; Mission 1. Read only the user specified period
; ==============================================================

    U_files  = systemfunc ("ls "+in_path1+"uwnd.*.nc")
    V_files  = systemfunc ("ls "+in_path2+"vwnd.*.nc")
    setfileoption ("nc","SuppressClose",False)   ;close too many files
    U_in = addfiles (U_files, "r")
    V_in = addfiles (V_files, "r")
    ListSetType (U_in, "cat")   ;concatenate or "merge" (default)
    ListSetType (V_in, "cat")

;    hgt = hgt_in[:]->hgt(:,2,:,:)   ;850 hPa
;    hgt = hgt_in[:]->hgt(:,5,:,:)   ;500 hPa
    U = U_in[:]->uwnd(:,8,::-1,:)   ;250 hPa
    V = V_in[:]->vwnd(:,8,::-1,:)   ;250 hPa
    printVarSummary (U)
    printVarSummary (V)

;---------------------------------------------------------------
; Read time and create required yyyyddd                    
    time    = U_in[:]->time
    TIME    = cd_calendar (time, 0)
    year    = toint ( TIME(:,0) )
    month   = toint ( TIME(:,1) )
    day     = toint ( TIME(:,2) )
    ddd     = day_of_year (year,month,day)
    yyyyddd = year*1000 + ddd      ;needed for input
    printVarSummary (yyyyddd)

;get the time indexs
    iMM = ind (month.ge.mS .and. month.le.mE)

; create the filter weights
    nwt = 61
    fca = 1./30.
    fcb = 1./10.
    ihp = 2          
    nsigma = 1.
    wts = filwgts_lanczos (nwt, ihp, fca, fcb, nsigma)   ; 10-30 day

;creat weights: cos(lat)
    rad = 4.*atan(1.)/180.
    gw  = U_in[0]->lat({latS:latN})
    gw  = cos (rad*gw)
    printVarSummary (gw)

; ==============================================================
; Mission 2. Post-post process data to deserved results
; ==============================================================

;stream function
   sfvp = uv2sfvpF (U,V)
   sf   = sfvp(0,:,:,:)
   copy_VarCoords (U,sf)
   sf = lonPivot (sf, 290)      ;reorder
   printVarSummary (sf)   

;calculate deviation from zonal mean
   sf_xAnom = dim_rmvmean_Wrap (sf)
   printVarSummary (sf_xAnom)

;Daily anomalies
   sfClmDay = clmDayTLL (sf_xAnom, yyyyddd)
   sf_tAnom = calcDayAnomTLL (sf_xAnom, yyyyddd, sfClmDay)
   printVarSummary(sf_tAnom)

;create LAT average
   sfAnom_reg = dim_avg_wgt_n_Wrap ( sf_tAnom(:,{latS:latN},:) ,gw,1,1)
   printVarSummary (sfAnom_reg)

;band pass filters
   sf_BPF_reg_p   = wgt_runave_Wrap (sfAnom_reg(lon|:,time|:),wts,0)
   sf_BPF_point_p = wgt_runave_Wrap (sf_tAnom({lat|lat},{lon|lon},time|:),wts,0)
   sf_BPF_reg     = sf_BPF_reg_p (:,iMM)
   sf_BPF_point   = sf_BPF_point_p (iMM)      ;get base point
   printVarSummary (sf_BPF_reg)
   printVarSummary (sf_BPF_point)

;---------------------------------------------------------------
;compute cross correlation
/;
   dim= dimsizes (sf_BPF_reg)

   ccr_n = esccr (sf_BPF_reg,sf_BPF_point,maxlag)
   ccr_n = ccr_n(:,::-1)
   ccr_p = esccr (sf_BPF_point,sf_BPF_reg,maxlag)

   ccr = new ((/dim(0),2*maxlag+1/),"float")
   copy_VarCoords_1 (sf_BPF_reg,ccr)

   ccr(:,:maxlag-1) = (/ccr_n(:,:maxlag-1)/)
   ccr(:,maxlag:)   = (/ccr_p/)

   ccr!1 = "time"
   ccr_c = ccr(time|:,lon|:)      ;reorder
   printVarSummary (ccr_c)
;/
   ccr_r = mjo_xcor_lag_season (sf_BPF_point,sf_BPF_reg(time|:,lon|:),maxlag,False)
   printVarSummary (ccr_r)

;determine the statistical significance
;   prob = ccr      ;copy meta data
;   prob = rtest (ccr,dim(0),0)
;   prob = mask (prob,prob.eq.0.,False)      ;set prob that are equal to 0 to the _FillValue
;   printVarSummary (prob_sm)


; ==============================================================
; Mission 3. Draw the correlation
; ==============================================================
 wks  = gsn_open_wks ("svg",out_path+out_name)

;-----------------------------------------------------------------------------
res                = True

;res@gsnLeftString   = lon+"E "+lat+"N"
res@gsnLeftString   = lon+"E "+lat+"N"
res@gsnCenterString = season
res@gsnRightString  = "AVG: "+latS+"-"+latN+"N"
res@gsnStringFontHeightF = .02

res@cnFillOn             = True
res@cnLinesOn            = False
res@cnFillPalette        = "CBR_coldhot"
res@cnLineLabelsOn       = False
res@cnLevelSelectionMode = "ExplicitLevels"
res@cnLevels             = (/ -.45, -.3,-.15,.15,.3,.45/)
res@cnMinLevelValF       = -0.45
res@cnMaxLevelValF       = 0.45
res@cnLevelSpacingF      = 0.15

res@tmYLMode             = "Explicit"      ;Define own tick mark labels.
;res@tmYLValues           = text1
;res@tmYLLabels           = text2
res@tmXBLabelFontHeightF = .02
res@tmYLLabelFontHeightF = .02
res@tmXBTickSpacingF     = 60.      ;label spacing

res@tiMainString  = "Hovmoller Diagram of One-point Lagged Correlation of SF"
res@tiYAxisString = "Lag (days)"

res@vpHeightF = 0.25

res@lbLabelFontHeightF = 0.02

res@pmLabelBarOrthogonalPosF = 0.03   ;move Label Bar down

plot = gsn_csm_hov (wks,ccr_r,res)

;---------------------------------------------------------------
;probability plots
;res2 = True

;res2@gsnDraw              = False            ;don't draw
;res2@gsnFrame             = False            ;don't advance frame
;res2@gsnLeftString        = " "
;res2@gsnRightString       = " "

;res2@cnLevelSelectionMode = "ManualLevels"   ;set manual contour levels
;res2@cnMinLevelValF       = 0.00             ;set min contour level
;res2@cnMaxLevelValF       = 0.10             ;set max contour level
;res2@cnLevelSpacingF      = 0.01             ;set contour spacing
;res2@cnInfoLabelOn        = False
;res2@cnLinesOn            = False            ;do not draw contour lines
;res2@cnLineLabelsOn       = False            ;do not draw contour labels
;res2@cnFillDotSizeF       = 0.003            ;set a uniform dot size
;res2@cnFillScaleF         = 1.2              ;add extra density

;plot2 = gsn_csm_contour (wks,prob,res2)
;plot2 = ShadeLtContour (plot2,0.015,17)      ;shade all areas < 0.015 contour
;plot3 = gsn_csm_contour (wks,prob,res2)
;plot3 = ShadeLtContour (plot3,0.015,17)      ;shade all areas < 0.015 contour
;overlay (plot(0),plot2)
;overlay (plot(1),plot3)

;*******************************************
;create panel resources
;*******************************************
;resP                  = True
;resP@txString         = "Lag Correlation for "+season+" 250 hPa Height"   ;add common title
;resP@txFontHeightF    = 0.024           ;height of text
;resP@gsnPanelCenter   = False           ;the plots to be not centered
;resP@gsnPanelLabelBar = True            ;add common colorbar
;resP@pmLabelBarOrthogonalPosF = -0.02   ;move Label Bar down

;gsn_panel(wks,plot,(/2,2/),resP)          ; create panel

end
