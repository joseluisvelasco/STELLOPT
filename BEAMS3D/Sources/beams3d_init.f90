!-----------------------------------------------------------------------
!     Module:        beams3d_init
!     Authors:       S. Lazerson (lazerson@pppl.gov), M. McMillan (matthew.mcmillan@my.wheaton.edu)
!     Date:          06/20/2012
!     Description:   This subroutine initializes the fields on the
!                    R, phi, Z grid.  
!-----------------------------------------------------------------------
      SUBROUTINE beams3d_init
!-----------------------------------------------------------------------
!     Libraries
!-----------------------------------------------------------------------
      USE stel_kinds, ONLY: rprec
      USE vmec_input,  ONLY: extcur_in => extcur, read_indata_namelist,&
                             nv_in => nzeta, nfp_in => nfp, nigroup
      USE read_eqdsk_mod, ONLY: read_gfile, get_eqdsk_grid
      USE read_hint_mod, ONLY: read_hint_mag, get_hint_grid
      USE beams3d_runtime
      USE beams3d_grid
      USE beams3d_input_mod, ONLY: read_beams3d_input
      USE beams3d_lines, ONLY: nparticles, epower_prof, ipower_prof, &
                               ndot_prof, j_prof, dense_prof, &
                               partvmax, partpmax, &
                               end_state, ns_prof1, ns_prof2, ns_prof3, &
                               ns_prof4, ns_prof5, dist5d_prof, win_dist5d, &
                               win_epower, win_ipower, win_ndot, win_jprof, &
                               win_dense, nsh_prof4, h2_prof, h3_prof, &
                               h4_prof, h5_prof
      USE wall_mod
      USE mpi_params
      USE adas_mod_parallel, ONLY: adas_load_tables, adas_tables_avail
      USE mpi_inc
      USE mpi_sharmem
      USE beams3d_physics_mod, ONLY: beams3d_suv2rzp ! remove if test below removed
!-----------------------------------------------------------------------
!     Local Variables
!          ier            Error Flag
!          iunit          File ID Number
!-----------------------------------------------------------------------
      IMPLICIT NONE
#if defined(NAG)
      LOGICAL        :: licval
      INTEGER        :: mkmaj, mkmin
      CHARACTER(128) :: impl,prec,pcode,hdware,opsys,fcomp,vend
#endif
      INTEGER :: i,j,k,ier, iunit, nextcur_in, nshar
      INTEGER :: bcs1(2), bcs2(2), bcs3(2), bcs1_s(2)
      REAL(rprec) :: br, bphi, bz, ti_temp, vtemp
      REAL(rprec), DIMENSION(:), ALLOCATABLE :: R_wall_temp
      REAL(rprec) :: stemp, utemp, rtemp, ztemp, phitemp
!-----------------------------------------------------------------------
!     External Functions
!          A00ADF               NAG Detection
!-----------------------------------------------------------------------
!      EXTERNAL A00ADF
!-----------------------------------------------------------------------
!     Begin Subroutine
!-----------------------------------------------------------------------
      bcs1=(/ 0, 0/)
      bcs2=(/-1,-1/)
      bcs3=(/ 0, 0/)
      !partvmax = 0.0
      partpmax = 9.10938356E-31 ! Electron mass
      
      ! If we pass a vessel then we want to use it for NBI injection
      lvessel_beam = .FALSE.
      IF (lvessel) lvessel_beam = .TRUE.

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Initialize Runtime from namelist
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      
      ! First Read The Input Namelist
      iunit = 11
      IF (lverb) WRITE(6,'(A)') '----- Input Parameters -----'
#if defined(MPI_OPT)
      CALL MPI_BARRIER(MPI_COMM_BEAMS,ierr_mpi)
      IF (ierr_mpi /= MPI_SUCCESS) CALL handle_err(MPI_BARRIER_ERR,'beams3d_init0',ierr_mpi)
#endif

      IF (lvmec.and. lread_input) THEN
         CALL read_beams3d_input('input.' // TRIM(id_string),ier)
         IF (lverb) WRITE(6,'(A)') '   FILE: input.' // TRIM(id_string)
      ELSE IF (lpies .and. lread_input) THEN
         CALL read_beams3d_input(TRIM(id_string) // '.in',ier)
         IF (lverb) WRITE(6,'(A)') '   FILE: ' // TRIM(id_string) // '.in'
      ELSE IF (lspec .and. lread_input) THEN
         CALL read_beams3d_input('input.' // TRIM(id_string),ier)
         IF (lverb) WRITE(6,'(A)') '   FILE: input.' // TRIM(id_string)
      ELSE IF (leqdsk .and. lread_input) THEN
         CALL read_beams3d_input('input.' // TRIM(id_string),ier)
         IF (lverb) WRITE(6,'(A)') '   FILE: input.' // TRIM(id_string)
         CALL read_gfile(eqdsk_string,ier)
         IF (lverb) WRITE(6,'(A)') '   G-FILE: '// TRIM(eqdsk_string)
         CALL get_eqdsk_grid(nr,nz,rmin,rmax,zmin,zmax)
         phimin = 0; phimax=pi2
      ELSE IF (lhint .and. lread_input) THEN
         CALL read_beams3d_input(TRIM(id_string)//'.input',ier)
         IF (lverb) WRITE(6,'(A)') '   FILE:     ' // TRIM(id_string) // '.input'
         IF (lverb) WRITE(6,'(A)') '   MAG_FILE: ' // TRIM(id_string) // '.magslice'
         CALL read_hint_mag(TRIM(id_string)//'.magslice',ier)
         phimin = 0
         CALL get_hint_grid(nr,nz,nphi,rmin,rmax,zmin,zmax,phimax)
      END IF

      IF (lrestart_particles) THEN
        ldepo = .false.
        lbbnbi = .false.
        lbeam = .false.
      END IF

      ! Handle existence of ADAS for NBI
      IF (lbeam .and. .not.lsuzuki .and. myid_sharmem==master) THEN
         lsuzuki = .not.adas_tables_avail()
      END IF
      CALL MPI_BCAST(lsuzuki,1,MPI_LOGICAL, master, MPI_COMM_SHARMEM,ierr_mpi)
      IF (ierr_mpi /= MPI_SUCCESS) CALL handle_err(MPI_BCAST_ERR,'beams3d_init:lsuzuki',ierr_mpi)

      ! Output some information
      IF (lverb .and. .not.lrestart_grid) THEN
         WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   R   = [',rmin,',',rmax,'];  NR:   ',nr
         WRITE(6,'(A,F8.5,A,F8.5,A,I4)') '   PHI = [',phimin,',',phimax,'];  NPHI: ',nphi
         WRITE(6,'(A,F8.5,A,F8.5,A,I4)') '   Z   = [',zmin,',',zmax,'];  NZ:   ',nz
         IF (lbeam) THEN
            WRITE(6,'(A,I8)')               '   # of Particles to Start: ', nparticles_start
            WRITE(6,'(A,I6)')                          '   # of Beams:   ', nbeams
         ELSEIF (lfusion) THEN
            WRITE(6,'(A,I8)')               '   # of Particles to Start: ', nparticles_start
            WRITE(6,'(A,I6)')                          '   # of species: ', nbeams
         ELSE
            WRITE(6,'(A,I8)')               '   # of Particles to Start: ', nparticles
         END IF
         IF (lvessel) WRITE(6,'(A)')    '   VESSEL: ' // TRIM(vessel_string)
         IF (lcoil) WRITE(6,'(A)')    '   COIL: ' // TRIM(coil_string)
         IF (lmgrid) WRITE(6,'(A)')    '   MGRID: ' // TRIM(mgrid_string)
         IF (lcollision) WRITE(6,'(A)') '   COLLISION OPERATOR ON!'
         IF (lkick) WRITE(6,'(A)') '   KICK MODEL ON!'
         IF (lvac)  WRITE(6,'(A)') '   VACUUM FIELDS ONLY!'
         IF (ldepo) WRITE(6,'(A)') '   DEPOSITION ONLY!'
         IF (lw7x) WRITE(6,'(A)') '   W7-X BEAM Model!'
         IF (lascot) WRITE(6,'(A)') '   ASCOT5 OUTPUT ON!'
         IF (lascotfl) WRITE(6,'(A)') '   ASCOT5 FIELDLINE OUTPUT ON!'
         IF (lascot4) WRITE(6,'(A)') '   ASCOT4 OUTPUT ON!'
         IF (lbbnbi) WRITE(6,'(A)') '   BEAMLET BEAM Model!'
         IF (lsuzuki) WRITE(6,'(A)') '   SUZUKI DEPOSITION MODEL!'
         IF (lfusion) WRITE(6,'(A)') '   NUCLEAR FUSION BIRTH MODEL!'
         IF (lplasma_only) WRITE(6,'(A)') '   MAGNETIC FIELD FROM PLASMA ONLY!'
         IF (lrestart_particles) WRITE(6,'(A)') '   Restarting particles!'
         IF (lrandomize .and. lbeam) WRITE(6,'(A)') '   Randomizing particle processor!'
         IF (npot > 0) WRITE(6,'(A)') '   RAIDAL ELECTRIC FIELD PRESENT!'
         CALL FLUSH(6)
      END IF

      ! Construct 1D splines
      bcs1_s=(/ 0, 0 /)
      IF ((lvmec .or. leqdsk .or. lhint) .and. .not.lvac) THEN
         IF (lverb) WRITE(6,'(A)') '----- Profile Parameters -----'
         ! TE
         IF (nte>0) THEN
            CALL EZspline_init(TE_spl_s,nte,bcs1_s,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init1',ier)
            TE_spl_s%isHermite   = 0
            TE_spl_s%x1          = TE_AUX_S(1:nte)
            CALL EZspline_setup(TE_spl_s,TE_AUX_F(1:nte),ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init2',ier)
            IF (lverb) WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   Te   = [', &
                        MINVAL(TE_AUX_F(1:nte))*1E-3,',',MAXVAL(TE_AUX_F(1:nte))*1E-3,'] keV;  NTE:   ',nte
         END IF
         ! TI
         IF (nti>0) THEN
            CALL EZspline_init(TI_spl_s,nti,bcs1_s,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init3',ier)
            TI_spl_s%isHermite   = 0
            TI_spl_s%x1          = TI_AUX_S(1:nti)
            CALL EZspline_setup(TI_spl_s,TI_AUX_F(1:nti),ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init4',ier)
            IF (lverb) WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   Ti   = [', &
                        MINVAL(TI_AUX_F(1:nti))*1E-3,',',MAXVAL(TI_AUX_F(1:nti))*1E-3,'] keV;  NTI:   ',nti
         END IF
         ! NE
         IF (nne>0) THEN
            ! Check values
            IF (ALL(NE_AUX_F(1:nne) < 1E4)) THEN
              IF (lverb) WRITE(6,'(A)') '   Rescaling Electron Density (1E18)'
              NE_AUX_F(1:nne) = NE_AUX_F(1:nne)*1E18
            END IF
            CALL EZspline_init(NE_spl_s,nne,bcs1_s,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init5',ier)
            NE_spl_s%x1          = NE_AUX_S(1:nne)
            NE_spl_s%isHermite   = 0
             CALL EZspline_setup(NE_spl_s,NE_AUX_F(1:nne),ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init6',ier)
            IF (lverb) WRITE(6,'(A,F9.5,A,F9.5,A,I4,A)') '   Ne   = [', &
                        MINVAL(NE_AUX_F(1:nne))*1E-20,',',MAXVAL(NE_AUX_F(1:nne))*1E-20,'] E20 m^-3;  NNE:   ',nne
         END IF
         ! ZEFF
         IF (nzeff>0) THEN
            CALL EZspline_init(ZEFF_spl_s,nzeff,bcs1_s,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init7',ier)
            ZEFF_spl_s%isHermite   = 0
            ZEFF_spl_s%x1          = ZEFF_AUX_S(1:nzeff)
            CALL EZspline_setup(ZEFF_spl_s,ZEFF_AUX_F(1:nzeff),ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init8',ier)
            IF (lverb) WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   Zeff = [', &
                        MINVAL(ZEFF_AUX_F(1:nzeff)),',',MAXVAL(ZEFF_AUX_F(1:nzeff)),'];  NZEFF: ',nzeff
         END IF
         ! POTENTIAL
         IF (npot>0) THEN
            CALL EZspline_init(POT_spl_s,npot,bcs1_s,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init9',ier)
            POT_spl_s%x1          = POT_AUX_S(1:npot)
            POT_spl_s%isHermite   = 0
            CALL EZspline_setup(POT_spl_s,POT_AUX_F(1:npot),ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init10',ier)
            IF (lverb) WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   V    = [', &
                        MINVAL(POT_AUX_F(1:npot))*1E-3,',',MAXVAL(POT_AUX_F(1:npot))*1E-3,'] kV;  NPOT: ',npot
         END IF

         IF (lverb) THEN
            WRITE(6,'(A,F9.5,A)') '   PLASMA_MASS =  ',plasma_mass/1.66053906660E-27,' amu' 
            WRITE(6,'(A,F9.5,A)') '   PLASMA_ZAVG =  ',plasma_zavg,' <Z>' 
            WRITE(6,'(A,F9.5,A)') '   PLASMA_ZMEAN =  ',plasma_zmean,' [Z]' 
         END IF
         
      END IF

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Initialize Background Grids
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      IF (lrestart_grid) THEN
         !CALL beams3d_init_restart
      ELSE
         ! Create the background grid
         CALL mpialloc(raxis, nr, myid_sharmem, 0, MPI_COMM_SHARMEM, win_raxis)
         CALL mpialloc(phiaxis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_phiaxis)
         CALL mpialloc(zaxis, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_zaxis)
         CALL mpialloc(hr, nr-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hr)
         CALL mpialloc(hp, nphi-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hp)
         CALL mpialloc(hz, nz-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hz)
         CALL mpialloc(hri, nr-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hri)
         CALL mpialloc(hpi, nphi-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hpi)
         CALL mpialloc(hzi, nz-1, myid_sharmem, 0, MPI_COMM_SHARMEM, win_hzi)
         CALL mpialloc(B_R, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_B_R)
         CALL mpialloc(B_PHI, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_B_PHI)
         CALL mpialloc(B_Z, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_B_Z)
         CALL mpialloc(MODB, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_MODB)
         CALL mpialloc(TE, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_TE)
         CALL mpialloc(NE, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_NE)
         CALL mpialloc(TI, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_TI)
         CALL mpialloc(ZEFF_ARR, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_ZEFF_ARR)
         CALL mpialloc(POT_ARR, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_POT_ARR)
         CALL mpialloc(S_ARR, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_S_ARR)
         CALL mpialloc(U_ARR, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_U_ARR)
         IF (myid_sharmem == 0) THEN
            FORALL(i = 1:nr) raxis(i) = (i-1)*(rmax-rmin)/(nr-1) + rmin
            FORALL(i = 1:nz) zaxis(i) = (i-1)*(zmax-zmin)/(nz-1) + zmin
            FORALL(i = 1:nphi) phiaxis(i) = (i-1)*(phimax-phimin)/(nphi-1) + phimin
            S_ARR = 1.5
            POT_ARR = 0
            ! Setup grid helpers
            ! Note: All helpers are defined in terms of differences on half grid
            !       so values are indexed from 1 to n-1.  Which we store at n
            !        i = MIN(MAX(COUNT(raxis < r_temp),1),nr-1)
            !        hr(i) = raxis(i+1) - raxis(i)
            !        hri    = one / hr
            FORALL(i = 1:nr-1) hr(i) = raxis(i+1) - raxis(i)
            FORALL(i = 1:nz-1) hz(i) = zaxis(i+1) - zaxis(i)
            FORALL(i = 1:nphi-1) hp(i) = phiaxis(i+1) - phiaxis(i)
            hri = one / hr
            hpi = one / hp
            hzi = one / hz
         END IF
         CALL MPI_BARRIER(MPI_COMM_SHARMEM, ier)
         ! Put the vacuum field on the background grid
         IF (lmgrid) THEN
            CALL beams3d_init_mgrid
         ELSE IF (lcoil) THEN
            CALL beams3d_init_coil
         END IF
      END IF

      ! Put the plasma field on the background grid
      IF (lvmec .and. .not.lvac) THEN
         CALL mpialloc(req_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_req_axis)
         CALL mpialloc(zeq_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_zeq_axis)
         CALL beams3d_init_vmec
      ELSE IF (lpies .and. .not.lvac) THEN
         !CALL beams3d_init_pies
      ELSE IF (lspec .and. .not.lvac) THEN
         !CALL beams3d_init_spec
      ELSE IF (lhint .and. .not.lvac) THEN
         CALL mpialloc(req_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_req_axis)
         CALL mpialloc(zeq_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_zeq_axis)
         CALL beams3d_init_hint
      ELSE IF (leqdsk) THEN
         CALL mpialloc(req_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_req_axis)
         CALL mpialloc(zeq_axis, nphi, myid_sharmem, 0, MPI_COMM_SHARMEM, win_zeq_axis)
         CALL beams3d_init_eqdsk
      END IF

      ! Adjust the torodial distribution function grid
      ns_prof3 = MAX(ns_prof3,8*NINT(pi2/phimax)) ! Min 8 per field period

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Initialize Vessel (we need nbeams here)
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      
      ! Load vessel if not done already vessel
      IF (lvessel .and. (.not. lwall_loaded)) THEN
         CALL wall_load_txt(TRIM(vessel_string),ier,lverb,MPI_COMM_BEAMS)
         IF (lverb) THEN
            IF (ier /=0 ) WRITE(6,'(A)') 'ERROR: Loading VESSEL : ' // TRIM(vessel_string)
            IF (ier ==-327 ) WRITE(6,'(A)') '   ZERO Area Triagle detected!!!!'
         END IF
      END IF

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Secondary Code Output
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! For testing I put this here
      IF (lascot4) THEN
         CALL beams3d_write_ascoth4('INIT')
      END IF
      IF (lascot) THEN
         CALL beams3d_write_ascoth5('INIT')
      END IF

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Setup Splines
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! Construct 3D Profile Splines
      IF (.not. lvac) THEN
         ! First Allocated Spline on master threads
         IF (myid_sharmem == 0) THEN
            CALL EZspline_init(TE_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: TE',ier)
            CALL EZspline_init(NE_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: NE',ier)
            CALL EZspline_init(TI_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: TI',ier)
            CALL EZspline_init(ZEFF_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: ZEFF',ier)
            TE_spl%isHermite   = 1
            NE_spl%isHermite   = 1
            TI_spl%isHermite   = 1
            ZEFF_spl%isHermite = 1
            TE_spl%x1   = raxis
            NE_spl%x1   = raxis
            TI_spl%x1   = raxis
            ZEFF_spl%x1 = raxis
            TE_spl%x2   = phiaxis
            NE_spl%x2   = phiaxis
            TI_spl%x2   = phiaxis
            ZEFF_spl%x2 = phiaxis
            TE_spl%x3   = zaxis
            NE_spl%x3   = zaxis
            TI_spl%x3   = zaxis
            ZEFF_spl%x3 = zaxis
            CALL EZspline_setup(TE_spl,TE,ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: TE',ier)
            CALL EZspline_setup(NE_spl,NE,ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: NE',ier)
            CALL EZspline_setup(TI_spl,TI,ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: TI',ier)
            CALL EZspline_setup(ZEFF_spl,ZEFF_ARR,ier,EXACT_DIM=.true.)
            IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init: ZEFF_ARR',ier)
         END IF
         ! Now allocate the 4D spline array (which is all we need)
         CALL mpialloc(TE4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_TE4D)
         CALL mpialloc(NE4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_NE4D)
         CALL mpialloc(TI4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_TI4D)
         CALL mpialloc(ZEFF4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_ZEFF4D)
         ! Now have master copy data over and free the splines
         IF (myid_sharmem == master) THEN
            TE4D = TE_SPL%fspl
            NE4D = NE_SPL%fspl
            TI4D = TI_SPL%fspl
            ZEFF4D = ZEFF_SPL%fspl
            CALL EZspline_free(TE_spl,ier)
            CALL EZspline_free(NE_spl,ier)
            CALL EZspline_free(TI_spl,ier)
            CALL EZspline_free(ZEFF_spl,ier)
         END IF
         CALL MPI_BARRIER(MPI_COMM_SHARMEM, ier)
      END IF
         
      ! Construct MODB
      IF (myid_sharmem == master) MODB = SQRT(B_R*B_R+B_PHI*B_PHI+B_Z*B_Z)


      ! Construct Splines on shared memory master nodes
      IF (myid_sharmem == master) THEN
         bcs1=(/ 0, 0/)
         bcs2=(/-1,-1/)
         bcs3=(/ 0, 0/)
         CALL EZspline_init(BR_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BR_spl',ier)
         CALL EZspline_init(BPHI_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BPHI_spl',ier)
         CALL EZspline_init(BZ_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BZ_spl',ier)
         CALL EZspline_init(MODB_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:MODB_spl',ier)
         CALL EZspline_init(S_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:S_spl',ier)
         CALL EZspline_init(U_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:U_spl',ier)
         CALL EZspline_init(POT_spl,nr,nphi,nz,bcs1,bcs2,bcs3,ier)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:POT_spl',ier)
         BR_spl%isHermite   = 1
         BR_spl%x1   = raxis
         BR_spl%x2   = phiaxis
         BR_spl%x3   = zaxis
         BPHI_spl%isHermite = 1
         BPHI_spl%x1 = raxis
         BPHI_spl%x2 = phiaxis
         BPHI_spl%x3 = zaxis
         BZ_spl%isHermite   = 1
         BZ_spl%x1   = raxis
         BZ_spl%x2   = phiaxis
         BZ_spl%x3   = zaxis
         MODB_spl%isHermite = 1
         MODB_spl%x1 = raxis
         MODB_spl%x2 = phiaxis
         MODB_spl%x3 = zaxis
         S_spl%isHermite = 1
         S_spl%x1 = raxis
         S_spl%x2 = phiaxis
         S_spl%x3 = zaxis
         U_spl%isHermite = 1
         U_spl%x1 = raxis
         U_spl%x2 = phiaxis
         U_spl%x3 = zaxis
         POT_spl%isHermite = 1
         POT_spl%x1 = raxis
         POT_spl%x2 = phiaxis
         POT_spl%x3 = zaxis
         CALL EZspline_setup(BR_spl,B_R,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BR_spl',ier)
         CALL EZspline_setup(BPHI_spl,B_PHI,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BPHI_spl',ier)
         CALL EZspline_setup(BZ_spl,B_Z,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:BZ_spl',ier)
         CALL EZspline_setup(MODB_spl,MODB,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:MODB_spl',ier)
         CALL EZspline_setup(S_spl,S_ARR,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:S_spl',ier)
         CALL EZspline_setup(U_spl,U_ARR,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:U_spl',ier)
         CALL EZspline_setup(POT_spl,POT_ARR,ier,EXACT_DIM=.true.)
         IF (ier /=0) CALL handle_err(EZSPLINE_ERR,'beams3d_init:POT_spl',ier)
      END IF
      ! Allocate Shared memory space
      CALL MPI_BARRIER(MPI_COMM_SHARMEM, ier)
      CALL mpialloc(BR4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_BR4D)
      CALL mpialloc(BPHI4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_BPHI4D)
      CALL mpialloc(BZ4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_BZ4D)
      CALL mpialloc(MODB4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_MODB4D)
      CALL mpialloc(S4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_S4D)
      CALL mpialloc(U4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_U4D)
      CALL mpialloc(POT4D, 8, nr, nphi, nz, myid_sharmem, 0, MPI_COMM_SHARMEM, win_POT4D)
      ! Copy Spline info to shared memory and Free
      IF (myid_sharmem == master) THEN
         BR4D = BR_SPL%fspl
         BPHI4D = BPHI_SPL%fspl
         BZ4D = BZ_SPL%fspl
         MODB4D = MODB_SPL%fspl
         S4D = S_SPL%fspl
         U4D = U_SPL%fspl
         POT4D = POT_SPL%fspl
         CALL EZspline_free(BR_spl,ier)
         CALL EZspline_free(BPHI_spl,ier)
         CALL EZspline_free(BZ_spl,ier)
         CALL EZspline_free(MODB_spl,ier)
         CALL EZspline_free(S_spl,ier)
         CALL EZspline_free(U_spl,ier)
         CALL EZspline_free(POT_spl,ier)
      END IF
      ! These are helpers for range
      eps1 = (rmax-rmin)*small
      eps2 = (phimax-phimin)*small
      eps3 = (zmax-zmin)*small

      ! Print Grid info to screen
      IF (lverb) THEN
         WRITE(6,'(A)')'----- Constructing Splines -----'
         WRITE(6,'(A,F9.5,A,F9.5,A,I4)') '   R   = [',MINVAL(raxis),',',MAXVAL(raxis),'];  NR:   ',nr
         WRITE(6,'(A,F8.5,A,F8.5,A,I4)') '   PHI = [',MINVAL(phiaxis),',',MAXVAL(phiaxis),'];  NPHI: ',nphi
         WRITE(6,'(A,F8.5,A,F8.5,A,I4)') '   Z   = [',MINVAL(zaxis),',',MAXVAL(zaxis),'];  NZ:   ',nz
         WRITE(6,'(A,I1)')               '   HERMITE FORM: ',1
         CALL FLUSH(6)
      END IF

      IF (myid_sharmem==master) CALL beams3d_volume !requires S_ARR

      ! Output Grid
      CALL beams3d_write('GRID_INIT')
      CALL mpidealloc(B_R,win_B_R)
      CALL mpidealloc(B_PHI,win_B_PHI)
      CALL mpidealloc(B_Z,win_B_Z)
      CALL mpidealloc(MODB,win_MODB)
      CALL mpidealloc(S_ARR,win_S_ARR)
      CALL mpidealloc(U_ARR,win_U_ARR)
      CALL mpidealloc(POT_ARR,win_POT_ARR)
      IF (.not. lvac) THEN
         CALL mpidealloc(TE,win_TE)
         CALL mpidealloc(NE,win_NE)
         CALL mpidealloc(TI,win_TI)
         CALL mpidealloc(ZEFF_ARR,win_ZEFF_ARR)
      END IF

      ! DEALLOCATE Variables
      IF (lvmec .and. .not.lvac) THEN
         IF (nte > 0) CALL EZspline_free(TE_spl_s,ier)
         IF (nne > 0) CALL EZspline_free(NE_spl_s,ier)
         IF (nti > 0) CALL EZspline_free(TI_spl_s,ier)
         IF (npot > 0) CALL EZspline_free(POT_spl_s,ier)
         IF (nzeff > 0) CALL EZspline_free(ZEFF_spl_s,ier)
      END IF

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Initialize Particles
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! Initialize Random Number generator
      CALL RANDOM_SEED
      
      ! Initialize beams (define a distribution of directions and weights)
      IF (lbeam) THEN
         IF (.not. lsuzuki) CALL adas_load_tables(myid_sharmem, MPI_COMM_SHARMEM)
         IF (lw7x) THEN
            CALL beams3d_init_beams_w7x
         ELSEIF (lbbnbi) THEN
            CALL beams3d_init_beams_bbnbi
         ELSE
            CALL beams3d_init_beams
         END IF
         ! Randomize particles Only for beam depo runs
         IF (lrandomize) CALL beams3d_randomize_particles
      ELSEIF (lrestart_particles) THEN
         CALL beams3d_init_restart
      ELSEIF (lfusion) THEN
         CALL beams3d_init_fusion
      ELSE
        ALLOCATE(  R_start(nparticles), phi_start(nparticles), Z_start(nparticles), &
           v_neut(3,nparticles), mass(nparticles), charge(nparticles), &
           mu_start(nparticles), Zatom(nparticles), t_end(nparticles), vll_start(nparticles), &
           beam(nparticles), weight(nparticles) )

         R_start = r_start_in(1:nparticles)
         phi_start = phi_start_in(1:nparticles)
         Z_start = z_start_in(1:nparticles)
         vll_start = vll_start_in(1:nparticles)
         v_neut = 0.0
         weight = 1.0/nparticles
         Zatom = Zatom_in(1:nparticles)
         mass = mass_in(1:nparticles)
         charge = charge_in(1:nparticles)
         mu_start = mu_start_in(1:nparticles)
         t_end = t_end_in(1:nparticles)
         beam  = 1
         nbeams = 1
         charge_beams(1) = charge_in(1)
         mass_beams(1)   = mass_in(1)
      END IF
      ! In all cases create an end_state array
      ALLOCATE(end_state(nparticles))
      end_state=0

      ! Setup distribution
      ALLOCATE(epower_prof(nbeams,ns_prof1), ipower_prof(nbeams,ns_prof1), &
               ndot_prof(nbeams,ns_prof1))
      ipower_prof=0; epower_prof=0; ndot_prof=0
      CALL mpialloc(dist5d_prof, nbeams, ns_prof1, ns_prof2, ns_prof3, ns_prof4, ns_prof5, myid_sharmem, 0, MPI_COMM_SHARMEM, win_dist5d)
      IF (myid_sharmem == master) THEN
         dist5d_prof = 0
      END IF
      h2_prof = ns_prof2*invpi2
      h3_prof = ns_prof3*invpi2

      ! Determine maximum particle velocity
      partvmax=MAX(MAXVAL(ABS(vll_start))*6.0/5.0,partvmax)
      !partpmax=MAX(MAXVAL(ABS(partvmax*mass)),partpmax)
      nsh_prof4 = ns_prof4/2
      h4_prof = 0.5*ns_prof4/partvmax
      h5_prof = ns_prof5/partvmax

      ! Do a reality check
      IF (ANY(ABS(vll_start)>3E8) .and. lverb) THEN
            ! This is an error code check
            PRINT *,'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
            PRINT *,'!!!!!  Super-luminal particle velocity detected  !!!!!'
            PRINT *,'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
            STOP
      END IF

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!              Wall Load Helpers here
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! Setup wall heat flux tracking
      IF (lwall_loaded) THEN
         IF (lverb) THEN
            CALL wall_info(6)
            ALLOCATE(R_wall_temp(nvertex))
            FORALL (i = 1:nvertex) R_wall_temp(i) = SQRT(vertex(i,1)*vertex(i,1)+vertex(i,2)*vertex(i,2))
            WRITE(6,'(A,F9.5,A,F9.5,A)') '   R_WALL   = [',MINVAL(R_wall_temp),',',MAXVAL(R_wall_temp),']'
            WRITE(6,'(A,F9.5,A,F9.5,A)') '   Z_WALL   = [',MINVAL(vertex(:,3)),',',MAXVAL(vertex(:,3)),']'
            IF ((MINVAL(R_wall_temp)<rmin) .or. &
                (MAXVAL(R_wall_temp)>rmax) .or. &
                (MINVAL(vertex(:,3))<zmin) .or. &
                (MAXVAL(vertex(:,3))>zmax)) THEN
               IF (.not. lplasma_only) WRITE(6,'(A)') '   WALL OUTSIDE GRID DOMAIN!'
            END IF
            DEALLOCATE(R_wall_temp)
         END IF
         CALL FLUSH(6)
         CALL mpialloc(wall_load, nbeams, nface, myid_sharmem, 0, MPI_COMM_SHARMEM, win_wall_load)
         IF (myid_sharmem == master) wall_load = 0
         CALL mpialloc(wall_shine, nbeams, nface, myid_sharmem, 0, MPI_COMM_SHARMEM, win_wall_shine)
         IF (myid_sharmem == master) wall_shine = 0
      END IF

      ! Some tests
      IF (.false. .and. lverb) THEN
         CALL beams3d_distnorm
         STOP
      END IF

#if defined(MPI_OPT)
      CALL MPI_BARRIER(MPI_COMM_BEAMS,ierr_mpi)
      IF (ierr_mpi /= MPI_SUCCESS) CALL handle_err(MPI_BARRIER_ERR,'beams3d_init',ierr_mpi)
#endif
!-----------------------------------------------------------------------
!     End Subroutine
!-----------------------------------------------------------------------    
      END SUBROUTINE beams3d_init
