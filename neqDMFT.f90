!###################################################################
!PURPOSE  : Solve conduction band electrons driven 
! by electric field interacting with a resevoir of free 
! electrons at temperature T
!AUTHORS  : Adriano Amaricci && Cedric Weber
!###################################################################
program neqDMFT
  USE VARS_GLOBAL                 !global variables, calls to 3rd library 
  USE ELECTRIC_FIELD              !contains electric field init && routines
  USE BATH                        !contains bath inizialization
  USE EQUILIBRIUM                 !solves the equilibrium problem w/ IPT
  USE IPT_NEQ                     !performs the non-eq. IPT. Write Sigma
  USE UPDATE_WF                   !contains routines for WF update and printing.
  USE KADANOFBAYM                 !solves KB equations numerically to get k-sum
  implicit none

  integer :: i
  logical :: converged

  call MPI_INIT(mpiERR)
  call MPI_COMM_RANK(MPI_COMM_WORLD,mpiID,mpiERR)
  call MPI_COMM_SIZE(MPI_COMM_WORLD,mpiSIZE,mpiERR)
  write(*,"(A,I4,A,I4,A)")'Processor ',mpiID,' of ',mpiSIZE,' is alive'
  call MPI_BARRIER(MPI_COMM_WORLD,mpiERR)

  !READ THE INPUT FILE (in vars_global):
  call read_input_init("inputFILE.in")

  !BUILD THE TIME,FREQUENCY GRIDS:
  include "grid_setup.f90"

  !BUILD THE 2D-SQUARE LATTICE STRUCTURE (in lib/square_lattice):
  Lk   = square_lattice_dimension(Nx,Ny)
  allocate(epsik(Lk),wt(Lk))
  wt   = square_lattice_structure(Lk,Nx,Ny)
  epsik= square_lattice_dispersion_array(Lk,ts)
  if(mpiID==0)call get_free_dos(epsik,wt)

  !SET THE ELECTRIC FIELD (in electric_field):
  call set_efield_vector()

  !ALLOCATE FUNCTIONS IN THE MEMORY (in vars_global):
  call global_memory_allocation

  !SOLVE THE EQUILIBRIUM PROBLEM WITH IPT (in equilibrium):
  if(solve_eq)call solve_equilibrium_ipt()

  !BUILD THE  DISSIPATIVE BATH FUNCTIONS (in bath):
  call get_thermostat_bath()


  !START DMFT LOOP SEQUENCE:
  !==============================================================
  !initialize the run by guessing/reading the self-energy functions (in IPT_NEQ.f90):
  call neq_init_run

  iloop=0;converged=.false.
  do while(.not.converged);iloop=iloop+1
     call start_loop(iloop,nloop,"DMFT-loop",unit=6)
     !
     call neq_get_localgf        !-|(in kadanoff-baym)

     call neq_update_weiss_field !-|SELF-CONSISTENCY (in funx_neq)
     if(iloop==2)stop
     !
     call neq_solve_ipt          !-|IMPURITY SOLVER (in ipt_neq)
     !
     ! call print_observables      !(in funx_neq)
     converged = convergence_check()
     call MPI_BCAST(converged,1,MPI_LOGICAL,0,MPI_COMM_WORLD,mpiERR)
     !
     call end_loop()
  enddo
  call msg("BRAVO")
  call MPI_BARRIER(MPI_COMM_WORLD,mpiERR)
  call MPI_FINALIZE(mpiERR)


contains


  !+-------------------------------------------------------------------+
  !PURPOSE  : check convergence of the calculation:
  !+-------------------------------------------------------------------+
  function convergence_check() result(converged)
    logical                         :: converged
    integer                         :: i,ik,ix,iy
    type(vect2D)                    :: Jk,Ak
    type(vect2D),dimension(0:nstep) :: Jloc                   !local Current 
    real(8),dimension(0:nstep)      :: test_func
    integer                         :: selector
    if(mpiID==0)then
       if(Efield/=0.d0)then
          Jloc=Vzero
          do ik=1,Lk
             ix=ik2ix(ik);iy=ik2iy(ik)
             do i=0,nstep
                Ak= Afield(t(i),Ek)
                Jk= nk(i,ik)*square_lattice_velocity(kgrid(ix,iy) - Ak)
                Jloc(i) = Jloc(i) +  wt(ik)*Jk
             enddo
          enddo
          test_func(0:nstep)=modulo(Jloc(0:nstep))
       else
          forall(i=0:nstep)test_func(i)=-xi*Sigma%less(i,i)!-xi*locG%less(i,i)
       endif
       converged=check_convergence(test_func(0:nstep),eps_error,Nsuccess,nloop,id=0)
    endif
  end function convergence_check



end PROGRAM neqDMFT
