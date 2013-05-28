!#####################################################################
!     Program  : VARS_GLOBAL
!     PURPOSE  : Defines the global variables used thru all the code
!     AUTHORS  : Adriano Amaricci
!#####################################################################
! NAME
! neqDMFT
! DESCRIPTION
!   Run the non-equilibrium DMFT in presence of an external electric field E. 
!   The field is controlled by few flags in the nml/cmd options. It can be 
!   constant, pulse or switched off smoothly. Many more fields can be added by  
!   simply coding them in ELECTRIC_FIELD.f90. The executable read the file
!   *inputFILE.ipt, if not found dump default values to a defualt file.
!
!   The output consist of very few data files that contain all the information,
!   these are eventually read by a second program *get_data_neqDMFT to extract 
!   all the relevant information.
!   In this version the impurity solver is: IPT
! OPTIONS (important)
!  dt=[0.1]            -- Time step for solution of KB equations
!  beta=[100.0]             -- Inverse temperature 
!  U=[6]                    -- Hubbard local interaction value
!  Efield=[0]               -- Strenght of the electric field
!  Vbath=[0]                -- Strenght of the coupling to bath (Lambda=Vbath^2/Wbath)
!  Wbath=[10.0]             -- Bandwidth of the fermionic thermostat
!  ts=[1]                   -- Hopping parameter
!  nstep=[50]               -- Number of time steps: T_max = dt*nstep
!  nloop=[30]               -- Maximum number of DMFT loops allowed (then exit)
!  eps_error=[1.d-4]        -- Tolerance on convergence
!  weight=[0.9]             -- Mixing parameter
!  Nsuccess =[2]            -- Number of consecutive success for convergence to be true
!  Ex=[1]                   -- X-component of the Electric field vector
!  Ey=[1]                   -- Y-component of the Electric field vector
!  t0=[0]                   -- Switching on time parameter for the Electric field
!  t1=[10^6]                -- Switching off time parameter for the Electric field
!  Ncycles=[3]              -- Number of cycles in the  gaussian packect envelope for the impulsive field. fix width.
!  omega0=[pi]            -- Frequency of the of the Oscillating Electric field        
!  E1=[0]                   -- Strenght of the electric field for the AC+DC case, to be tuned to resonate
!  field_type=[dc]       -- Type of electric field profile (dc,ac,ac+dc,etc..)
!  bath_type=[flat]     -- Fermionic thermostat type (constant,gaussian,bethe,etc..)
!  int_method=["trapz"]     -- 
!  data_dir=[DATAneq]       -- Name of the directory containing data files
!  plot_dir=[PLOT]          -- Name of the directory containing plot files
!  fchi=[F]                 -- Flag for the calculation of the optical response
!  L=[1024]                 -- A large number for whatever reason
!  Ltau=[200]               -- A large number for whatever reason
!  P=[5]                    -- Uniform Power mesh power-mesh parameter
!  Q=[5]                    -- Uniform Power mesh uniform-mesh parameter
!  eps=[0.05d0]             -- Broadening on the real-axis
!  Nx=[50]                  -- Number of k-points along x-axis 
!  Ny=[50]                  -- Number of k-points along y-axis 
!  solve_wfftw =[F]         -- 
!  plot3D=[F]       -- 
!  Lkreduced=[200]  -- 
!  eps=[0.05d0]         -- 
!  irdSFILE=[restartSigma]-- 
!  irdNkFILE=[restartNk]-- 
!#####################################################################
MODULE VARS_GLOBAL
  !Local:
  USE CONTOUR_GF
  !SciFor library
  USE SCIFOR_VERSION
  USE COMMON_VARS
  USE PARSE_CMD
  USE GREENFUNX
  USE TIMER
  USE VECTORS
  USE SQUARE_LATTICE
  USE INTEGRATE
  USE IOTOOLS
  USE FFTGF
  USE FUNCTIONS
  USE SPLINE
  USE TOOLS
  USE MPI
  implicit none

  !Version revision
  include "revision.inc"

  !Gloabl  variables
  !=========================================================
  integer                                :: nstep         !Number of Time steps
  integer                                :: L             !a big number
  integer                                :: Ltau          !Imaginary time slices
  integer                                :: Lk            !total lattice  dimension
  integer                                :: Lkreduced     !reduced lattice dimension
  integer                                :: Nx,Ny         !lattice grid dimensions
  integer                                :: iloop,nloop    !dmft loop variables
  integer                                :: eqnloop        !dmft loop of the equilibrium solution
  real(8)                                :: ts             !n.n./n.n.n. hopping amplitude
  real(8)                                :: u              !local,non-local interaction 
  real(8)                                :: Vbath          !Hopping amplitude to the BATH
  real(8)                                :: Wbath          !Width of the BATH DOS
  real(8)                                :: dt,dtau        !time step
  real(8)                                :: fmesh          !freq. step
  real(8)                                :: beta           !inverse temperature
  real(8)                                :: eps            !broadening
  character(len=16)                      :: int_method    !choose the integration method (rect,trapz,simps)
  character(len=16)                      :: bath_type     !choose the shape of the BATH
  character(len=16)                      :: field_type !choose the profile of the electric field
  real(8)                                :: eps_error     !convergence error threshold
  integer                                :: Nsuccess      !number of convergence success
  real(8)                                :: weight        !mixing weight parameter
  real(8)                                :: wmin,wmax     !min/max frequency
  real(8)                                :: tmin,tmax     !min/max time
  real(8)                                :: Walpha         !exponent of the pseudo-gapped bath.
  real(8)                                :: Wgap          !gap of the gapped bath
  logical                                :: plot3D,fchi
  logical                                :: solve_eq
  integer                                :: fupdate !flag to decide WFupdate procedure
  !

  !FILES TO RESTART
  !=========================================================
  character(len=32)                      :: irdSFILE,irdNkFILE


  !FREQS & TIME ARRAYS:
  !=========================================================  
  real(8),dimension(:),allocatable       :: wr,t,wm
  real(8),dimension(:),allocatable       :: tau


  !LATTICE (weight & dispersion) ARRAYS:
  !=========================================================  
  real(8),dimension(:),allocatable       :: wt,epsik


  !ELECTRIC FIELD VARIABLES (& NML):
  !=========================================================  
  type(vect2D)                           :: Ak,Ek         !Electric field vector potential and vector
  real(8)                                :: Efield        !Electric field strength
  real(8)                                :: Ex,Ey         !Electric field vectors as input
  real(8)                                :: t0,t1         !turn on/off time, t0 also center of the pulse
  integer                                :: Ncycles       !Number of cycles in pulsed light packet
  real(8)                                :: omega0        !parameter for the Oscilatting field and Pulsed light
  real(8)                                :: E1            !Electric field strenght for the AC+DC case (tune to resonate)

  !EQUILIUBRIUM (and Wigner transformed) GREEN'S FUNCTION 
  !=========================================================
  type(keldysh_equilibrium_gf)           :: gf0
  type(keldysh_equilibrium_gf)           :: gf
  type(keldysh_equilibrium_gf)           :: sf
  real(8),dimension(:),allocatable       :: exa


  !NON-EQUILIBRIUM FUNCTIONS:
  !=========================================================  
  !WEISS-FIELDS
  type(keldysh_contour_gf) :: G0
  !SELF-ENERGY
  type(keldysh_contour_gf) :: Sigma
  !LOCAL GF
  type(keldysh_contour_gf) :: locG
  !Bath SELF-ENERGY
  type(keldysh_contour_gf) :: S0



  !MOMENTUM-DISTRIBUTION
  !=========================================================  
  real(8),allocatable,dimension(:,:)     :: nk
  real(8),allocatable,dimension(:)       :: eq_nk


  !SUSCEPTIBILITY ARRAYS (in KADANOFF-BAYM)
  !=========================================================  
  real(8),allocatable,dimension(:,:,:,:) :: chi



  !DATA DIRECTORY:
  !=========================================================
  character(len=32)                      :: data_dir,plot_dir


  !NAMELISTS:
  !=========================================================
  namelist/variables/&
       dt,&
       beta,&
       Nstep        ,& 
       U            ,& 
       ts           ,& 
       eps          ,& 
       L            ,& 
       Ltau         ,& 
       Lkreduced    ,& 
                                !DMFT
       nloop        ,& 
       eqnloop      ,& 
                                !BATH:
       bath_type    ,& 
       Vbath        ,& 
       Wbath        ,& 
       Walpha       ,&
       Wgap         ,&
                                !FIELD:
       Efield       ,& 
       field_type   ,& 
       Ex           ,& 
       Ey           ,& 
       t0           ,& 
       t1           ,& 
       Ncycles      ,& 
       omega0       ,& 
       E1           ,& 
                                !K-GRID
       Nx           ,& 
       Ny           ,& 
                                !CONVERGENCE:
       eps_error    ,& 
       nsuccess     ,& 
       weight       ,& 
                                !FLAGS:
       int_method   ,& 
       solve_eq     ,& 
       plot3D       ,& 
       fchi         ,& 
       fupdate      ,&
                                !FILES&DIR:
       irdSFILE      ,& 
       irdNkFILE     ,& 
       data_dir     ,& 
       plot_dir



contains

  !+----------------------------------------------------------------+
  !PROGRAM  : READinput
  !TYPE     : subroutine
  !PURPOSE  : Read input file
  !+----------------------------------------------------------------+
  subroutine read_input_init(inputFILE)
    character(len=*)               :: inputFILE
    character(len=256),allocatable :: help_buffer(:)
    integer                        :: i
    logical                        :: control

    call version(revision)

    !GLOBAL
    dt           = 0.1d0
    beta         = 10.d0
    Nstep        = 100
    U            = 4.d0
    ts           = 1.d0
    eps          = 0.01d0
    L            = 2048  
    Ltau         = 200
    Lkreduced    = 300
    !DMFT
    nloop        = 30
    eqnloop      = 50
    !BATH:
    bath_type    = 'flat'
    Vbath        = 0.d0
    Wbath        = 20.d0
    Walpha       = 1.d0
    Wgap         = 5.d0
    !FIELD:
    Efield       = 0.d0
    field_type   = 'dc'
    Ex           = 1.d0
    Ey           = 0.d0
    t0           = 0.d0
    t1           = 1.d9
    Ncycles      = 1
    omega0       = 1.d0*pi
    E1           = 0.d0
    !K-GRID
    Nx           = 25
    Ny           = 25
    !CONVERGENCE:
    eps_error    = 1.d-4
    nsuccess     = 2
    weight       = 1.d0
    !FLAGS:
    int_method   = 'trapz'
    solve_eq     = .false. 
    plot3D       = .false.
    fchi         = .false.
    fupdate      = 0
    !FILES&DIR:
    irdSFILE      = 'restartSigma'
    irdNkFILE      = 'restartNk'
    data_dir     = 'DATAneq'
    plot_dir     = 'PLOT'

    inquire(file=adjustl(trim(inputFILE)),exist=control)
    if(control)then
       open(10,file=adjustl(trim(inputFILE)))
       read(10,nml=variables)
       close(10)
    else
       print*,"Can not find INPUT file"
       print*,"Dumping a default version in default."//trim(inputFILE)
       call dump_input_file("default.")
       call error("Can not find INPUT file, dumping a default version in default."//trim(inputFILE))
    endif

    !GLOBAL
    call parse_cmd_variable(dt           ,"DT")
    call parse_cmd_variable(beta         ,"BETA")
    call parse_cmd_variable(nstep        ,"NSTEP")
    call parse_cmd_variable(U            ,"U")
    call parse_cmd_variable(ts           ,"TS")
    call parse_cmd_variable(eps          ,"EPS")
    call parse_cmd_variable(L            ,"L")
    call parse_cmd_variable(Ltau         ,"LTAU")
    call parse_cmd_variable(Lkreduced    ,"LKREDUCED")
    !DMFT
    call parse_cmd_variable(nloop        ,"NLOOP")
    call parse_cmd_variable(eqnloop      ,"EQNLOOP")
    !BATH
    call parse_cmd_variable(Vbath        ,"VBATH")
    call parse_cmd_variable(bath_type    ,"BATH_TYPE")
    call parse_cmd_variable(wbath        ,"WBATH")
    call parse_cmd_variable(walpha       ,"WALPHA")
    call parse_cmd_variable(wgap         ,"WGAP")
    !EFIELD
    call parse_cmd_variable(field_type   ,"FIELD_TYPE")
    call parse_cmd_variable(Efield       ,"EFIELD")
    call parse_cmd_variable(Ex           ,"EX")
    call parse_cmd_variable(Ey           ,"EY")
    call parse_cmd_variable(t0           ,"T0")
    call parse_cmd_variable(t1           ,"T1")
    call parse_cmd_variable(ncycles      ,"NCYCLES")
    call parse_cmd_variable(omega0       ,"OMEGA0")
    call parse_cmd_variable(E1           ,"E1")
    !CONVERGENCE:
    call parse_cmd_variable(eps_error    ,"EPS_ERROR")
    call parse_cmd_variable(Nsuccess     ,"NSUCCESS")
    call parse_cmd_variable(weight       ,"WEIGHT")
    !GRID k-POINTS:
    call parse_cmd_variable(Nx           ,"NX")
    call parse_cmd_variable(Ny           ,"NY")
    !FLAGS:
    call parse_cmd_variable(int_method   ,"INT_METHOD")
    call parse_cmd_variable(solve_eq     ,"SOLVE_EQ")
    call parse_cmd_variable(plot3D       ,"PLOT3D")
    call parse_cmd_variable(fchi         ,"FCHI")
    call parse_cmd_variable(fupdate      ,"FUPDATE")
    !FILES&DIR:
    call parse_cmd_variable(irdSFILE      ,"IRDSFILE")
    call parse_cmd_variable(irdNkFILE     ,"IRDNKFILE")
    call parse_cmd_variable(data_dir     ,"DATA_DIR")
    call parse_cmd_variable(plot_dir     ,"PLOT_DIR")

    if(U==0.d0)Nloop=1

    if(mpiID==0)then
       write(*,*)"CONTROL PARAMETERS"
       write(*,nml=variables)
       write(*,*)"--------------------------------------------"
       write(*,*)""
       call dump_input_file("used.")
    endif

    call create_data_dir(trim(data_dir))
    if(plot3D)call create_data_dir(trim(plot_dir))

  contains
    subroutine dump_input_file(prefix)
      character(len=*) :: prefix
      if(mpiID==0)then
         open(10,file=trim(adjustl(trim(prefix)))//adjustl(trim(inputFILE)))
         write(10,nml=variables)
         close(10)
      endif
    end subroutine dump_input_file
  end subroutine read_input_init
  !******************************************************************
  !******************************************************************
  !******************************************************************





  !+----------------------------------------------------------------+
  !PURPOSE  : massive allocation of work array
  !+----------------------------------------------------------------+
  subroutine global_memory_allocation()
    integer          :: i
    real(8)          :: ex
    call msg("Allocating the memory")
    !Weiss-fields:
    call allocate_keldysh_contour_gf(G0,Nstep)    
    !Interaction self-energies:
    call allocate_keldysh_contour_gf(Sigma,Nstep)
    !Local Green's functions:
    call allocate_keldysh_contour_gf(locG,Nstep)
    !Bath self-energies:
    call allocate_keldysh_contour_gf(S0,Nstep)
    !Momentum-distribution:
    allocate(nk(0:nstep,Lk),eq_nk(Lk))
    !Equilibrium/Wigner rotated Green's function
    call allocate_gf(gf0,nstep)
    call allocate_gf(gf,nstep)
    call allocate_gf(sf,nstep)

    !Susceptibility/Optical response
    if(fchi)allocate(chi(2,2,0:nstep,0:nstep))
    !Other:
    allocate(exa(-nstep:nstep))
    ex=-1.d0       
    do i=-nstep,nstep
       ex=-ex
       exa(i)=ex
    enddo
  end subroutine global_memory_allocation

  !******************************************************************
  !******************************************************************
  !******************************************************************


end module VARS_GLOBAL

