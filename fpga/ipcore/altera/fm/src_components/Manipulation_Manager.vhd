
-- ******************************************************************************************
-- *                                Manipulation_Manager                                    *
-- ******************************************************************************************
-- *                                                                                        *
-- * component for selecting the right task and passing trough the manipulations to the     *
-- * other components                                                                       *
-- *                                                                                        *
-- * It starts counting the following POWERLINK-cycles by detecting the SoCs. It is reading *
-- * the tasks and selecting the fitting one.                                               *
-- *                                                                                        *
-- *----------------------------------------------------------------------------------------*
-- *                                                                                        *
-- * 09.08.12 V1.0      Manipulation_Manager                    by Sebastian Muelhausen     *
-- *                                                                                        *
-- ******************************************************************************************

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Manipulation_Manager is
    generic(
            gFrom:              natural:=15;
            gTo :               natural:=22;
            gWordWidth:         natural:=64;
            gManiSettingWidth:  natural:=112;
            gCycleCntWidth:     natural:=8;
            gBuffAddrWidth:     natural:=5
        );
    port(
        clk, reset:         in std_logic;
        --control signals
        iStartFrameProcess: in std_logic;   --Valid Frame received for processing
        iFrameSync:         in std_logic;   --sync for collecting header-data
        iStartTest:         in std_logic;   --start series of test
        iStopTest:          in std_logic;   --stop test
        oStartFrameStorage: out std_logic;  --valid frame was compared and can be stored
        oTestSync:          out std_logic;  --sync of a new test
        oTestActive:        out std_logic;  --series of test is currently running
        oFrameIsSoc:        out std_logic;  --current frame is a SoC
        --data signals
        iData:              in std_logic_vector(7 downto 0);                    --frame-stream
        iTaskSettingData:   in std_logic_vector(2*gWordWidth-1 downto 0);       --settings for the tasks
        iTaskCompFrame:     in std_logic_vector(gWordWidth-1 downto 0);         --frame-header-data for the tasks
        iTaskCompMask:      in std_logic_vector(gWordWidth-1 downto 0);         --frame-mask for the tasks
        oTaskSelection:     out std_logic_vector(gBuffAddrWidth-1 downto 0);    --Task selection
        --manipulations
        oTaskDelayEn:       out std_logic;                                      --task: delay frame
        oTaskManiEn:        out std_logic;                                      --task: manipulate header
        oTaskCrcEn:         out std_logic;                                      --task: distort crc
        oTaskCutEn:         out std_logic;                                      --task: truncate frame
        oManiSetting:       out std_logic_vector(gManiSettingWidth-1 downto 0)  --manipulation setting
     );
end Manipulation_Manager;

architecture two_seg_arch of Manipulation_Manager is

    --Data collector of the ethernet header
    component Frame_collector
        generic(
            gFrom:natural:=13;
            gTo : natural:=22
        );
        port(
            clk, reset:         in std_logic;
            iData:              in std_logic_vector(7 downto 0);
            iSync:              in std_logic;
            oFrameData :        out std_logic_vector((gTo-gFrom+1)*8-1 downto 0);
            oCollectorFinished: out std_logic
        );
    end component;

    --Logic for reading the task-memory
    component read_logic
        generic(
            gPrescaler:natural:=4;
            gAddrWidth: natural:=11);
        port(
            clk, reset: in std_logic;
            iEn:    in std_logic;
            iSync:  in std_logic;
            iStartAddr: in std_logic_vector(gAddrWidth-1 downto 0);
            oAddr:  out  std_logic_vector(gAddrWidth-1 downto 0)
        );
    end component;

    --Cnter, which counts the SoCs
    component SoC_Cnter
        generic(gCnterWidth:natural:=8);
        port(
            clk, reset:     in std_logic;
            iTestSync:      in std_logic;                   --sync for counter reset
            iFrameSync:     in std_logic;                   --sync for new incoming frame
            iEn:            in std_logic;                   --counter enable
            iData:          in std_logic_vector(7 downto 0);--frame-data
            oFrameIsSoc:    out std_logic;                  --current frame is a SoC
            oSocCnt  :      out std_logic_vector(7 downto 0)--number of received SoCs
        );
    end component;

    --Test signals
    signal regStartTest:        std_logic;  --start register for edge detection
    signal TestActive:          std_logic;  --test is active
    signal TestSync:            std_logic;  --reset for new test

    --collector signals
    signal CollFinished:        std_logic;                                  --collector received the header data
    signal HeaderData:          std_logic_vector(gWordWidth-1 downto 0);    --received header data

    --memory signals
    signal ReadEn:              std_logic;                                  --read task-buffer
    signal TaskSelection:       std_logic_vector(gBuffAddrWidth-1 downto 0);--task address

    --cycle variables
    signal CurrentCycle:        std_logic_vector(gCycleCntWidth-1 downto 0);--current PL Cycle of the Ssries of test
    signal TaskCycle:           std_logic_vector(gCycleCntWidth-1 downto 0);--cycle number of the task
    signal CycleLastTask:       std_logic_vector(gCycleCntWidth-1 downto 0);--cycle number of the last task
    signal CycleLastTask_next:  std_logic_vector(gCycleCntWidth-1 downto 0);--next cycle number of the last task

    --task variables
    signal TaskEmpty:           std_logic;  --current task consists of zeroes => reached end of task
    signal HeaderConformance:   std_logic;  --frame header fits with the frame of the task
    signal SelectedTask:        std_logic;  --conformance with header an POWRLINK-cycle
    signal CompFinished:        std_logic;  --all tasks were compared

    --manipulation tasks:
    signal TaskDropEn:          std_logic;                                                  --drop frame
    signal ManiSetting:         std_logic_vector(2*gWordWidth-gCycleCntWidth-1 downto 0);   --settings for the task
    signal ManiSetting_next:    std_logic_vector(2*gWordWidth-gCycleCntWidth-1 downto 0);


begin

    --MENAGER CONTROL (start, stop, ...)-------------------------------------------------------

    --Test is active RS-FF:
    process(clk)
    begin
        if (clk'event and clk='1') then

            if (reset='1') then
                regStartTest<='0';
                TestActive<='0';

            else
                regStartTest<=iStartTest;

                if TestSync='1' then
                    TestActive<='1';    --set active on test start

                elsif (CurrentCycle=(gCycleCntWidth-1 downto 0 => '1'))or(iStopTest='1')
                                    or unsigned(CurrentCycle)>unsigned(CycleLastTask) then
                    TestActive<='0';    --set inactive, when cycle-counter reached its limit (="11...1")
                                                    --  when test is stoped by an operations
                                                    --  when the last task was processed (current>lastTask)

                end if;

            end if;

        end if;
    end process;

    --Test reset after positive edge of start signal
    TestSync<= '1' when (iStartTest='1' and regStartTest='0')  else '0';
    oTestSync<=TestSync;

    --Soc Counter: counts PL-cycles as long as TestActive is '1'
    CycleCnter:SoC_Cnter
    generic map(gCnterWidth=>gCycleCntWidth)
    port map(
            clk=>clk,reset=>reset,
            iTestSync=>TestSync,        iFrameSync=>iFrameSync, iEn=>TestActive,    iData=>iData,
            oFrameIsSoc=>oFrameIsSoc,   oSocCnt=>CurrentCycle);
    ---------------------------------------------------------------------------------------------



    --DATA GATHERING (collecting header-data, reading tasks)--------------------------------------

    --Header data collector
    FC:Frame_collector
    generic map(gFrom=>gFrom,gTo=>gTo)
    port map(
            clk=>clk,reset=>reset,
            iData=>iData, iSync=>iFrameSync,
            oFrameData=>HeaderData, oCollectorFinished=>CollFinished);


    --enable task-reading, when header-data are ready and the manager is still comparing the tasks
    ReadEn<='1' when (CollFinished='1' and CompFinished='0') else '0';

    --logic for reading the task-data
    CommandRL:read_logic
    generic map(gPrescaler=>1,gAddrWidth=>gBuffAddrWidth)
    port map(
            clk=>clk,               reset=>reset,
            iEn=>ReadEn,            iSync=>iFrameSync,      iStartAddr=>(others=>'0'),
            oAddr=>TaskSelection);

    --Comparing has finished, when the last entry or an gap was reached
    CompFinished<= '1' when (to_integer(unsigned(TaskSelection))+1=2**gBuffAddrWidth)
                                or TaskEmpty='1' else '0';

    --current task is empty => gap
    TaskEmpty<= '1' when iTaskSettingData=(iTaskSettingData'range=>'0')
                            and iTaskCompFrame=(iTaskCompFrame'range=>'0')
                            and iTaskCompMask=(iTaskCompMask'range=>'0') else '0';
    ---------------------------------------------------------------------------------------------



    --TASK SELECTING(compare of setting and cycle number)----------------------------------------

    --Header fits with the task-data
    HeaderConformance <= '1' when ((HeaderData xor iTaskCompFrame)
                                    and iTaskCompMask)=(HeaderData'range=>'0') else '0';

    --first Byte: Cycle of the task
    TaskCycle<=     iTaskSettingData(iTaskSettingData'left downto iTaskSettingData'left-gCycleCntWidth+1);

    --storing the last cycle of all tasks
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                CycleLastTask<=(others => '0');
            else
                CycleLastTask <= CycleLastTask_next;
            end if;
        end if;
    end process;

    CycleLastTask_next <= (0=>'1', others => '0') when TestActive = '0' else --at least a series of test with one PL cycle
                          TaskCycle when unsigned(TaskCycle) > unsigned(CycleLastTask) and ReadEn = '1' else
                          CycleLastTask;

    --Task Cycle=current cycle => Frame fits with selected task
    SelectedTask<= '1' when (HeaderConformance='1' and CollFinished='1' and TestActive='1'
                        and (CurrentCycle=TaskCycle or TaskCycle=X"FF") ) else '0';
    ---------------------------------------------------------------------------------------------



    --DATA HANDLING (select the right manipulation, output)----------------------------------

    --storing data
    process(iFrameSync,SelectedTask,iTaskSettingData)
    begin
        if (SelectedTask='1') then          --task fits => store setting
            ManiSetting_next<= iTaskSettingData(ManiSetting_next'left downto 0);

        elsif (iFrameSync='1') then         --reset => delete setting
            ManiSetting_next<=(others=>'0');

        else                                --task doesn't fit => keep data
            ManiSetting_next<= ManiSetting;

        end if;
    end process;

    process(clk, reset)
    begin
        if (reset='1') then
            ManiSetting <= (others=>'0');

        elsif (clk'event and clk='1') then
            ManiSetting<=ManiSetting_next;

        end if;
    end process;


    --Second Byte: Definnition of the kind of manipulation in one hot coded
    TaskDropEn<=    ManiSetting(ManiSetting'length-8);  --Second Byte = 0x01
    oTaskDelayEn<=  ManiSetting(ManiSetting'length-7);  --Second Byte = 0x02
    oTaskManiEn<=   ManiSetting(ManiSetting'length-6);  --Second Byte = 0x04
    oTaskCrcEn<=    ManiSetting(ManiSetting'length-5);  --Second Byte = 0x08
    oTaskCutEn<=    ManiSetting(ManiSetting'length-4);  --Second Byte = 0x10

    --output
    oManiSetting <= ManiSetting(oManiSetting'left downto 0);
    oTaskSelection<=TaskSelection;
    oTestActive<=TestActive;

    --frame can be stored, after comparing and not dropping the frame
    oStartFrameStorage<=iStartFrameProcess and CompFinished and not TaskDropEn;

end two_seg_arch;